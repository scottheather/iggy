-- create spatial indices
create index if not exists building_footprints_idx on building_footprints using gist(wkb_geometry);
create index if not exists certificate_occupancy_idx on certificate_occupancy using gist(wkb_geometry);
create index if not exists liquor_idx on liquor_licenses using gist(wkb_geometry);
create index if not exists osm_bars_idx on osm_bars using gist(wkb_geometry);

create extension if not exists fuzzystrmatch;

-- lots of bars have closed since onset of pandemic, 
-- try to match bars with liquor license

alter table osm_bars add column liquor_license BOOLEAN;
update osm_bars a
set liquor_license = True
from liquor_licenses b
where ST_DWITHIN(a.wkb_geometry,b.wkb_geometry,50)
and levenshtein(a.name,b.trade_name,0,1,1) <= 4
or levenshtein(a.name,b.applicant,0,1,1) <= 4;


-- find bars that don't intersect with a building footprint (40)
select
	a.name,
	a.address,
	a.wkb_geometry
from osm_bars a
left join 
	building_footprints bf
	on st_intersects(a.wkb_geometry,bf.wkb_geometry)
	where bf.ogc_fid is null;
	
-- find duplicate bar names (2)
select 
	name, count(*)
	from osm_bars
	group by "name"
	having count(*) > 1;

-- duplicate bars at addresses (8)
select 
	address, count(*)
	from osm_bars
	group by address
	having count(*) > 1;

---- 
do
$do$
BEGIN
	if exists 
		(select *
		from information_schema."tables"
		where table_schema ='public'
		and table_name = 'get_addresses')
	then	
		update osm_bars a
		set address = b.address
		from get_addresses b
		where a.osm_id = b.osm_id;
	end if;
end
$do$;

-- create a voronoi of occupancy certificates against bldg footprints to subdivide buildings

drop table cert_occ_voronoi_building_ftprnt;
with voronoi as(
	select
		(ST_Dump(ST_VoronoiPolygons(ST_Collect(wkb_geometry)))).geom as geom
	from certificate_occupancy),
	voronoi_joined as(
	select 
		a.address,
		a.issue_date,
		a.description_of_occupancy,
		a.floors_occupied,
		a.trading_as,
		a.occupancy_load,
		a.wkb_geometry,
		b.geom
	from certificate_occupancy a
	join voronoi b
	on ST_INTERSECTS(a.wkb_geometry,b.geom))
	select 
	a.address,
	a.issue_date,
	a.description_of_occupancy,
	a.floors_occupied,
	a.trading_as,
	a.occupancy_load,
	ST_INTERSECTION(a.geom,b.wkb_geometry) as geom
	into cert_occ_voronoi_building_ftprnt
	from voronoi_joined a
	join building_footprints b
	on ST_INTERSECTS(a.wkb_geometry,b.wkb_geometry);

-- there are a lot of certificates with the same name, same address
-- try to group these "duplicates" together

drop table if exists certificate_voronoi_grouped;
select 
	max(issue_date) as issue_date,
	max(floors_occupied) as floors_occupied,
	max(occupancy_load) as occupancy_load,
	max(description_of_occupancy) as description_of_occupancy,
	max(address) as address,
	trading_as,
	geom
into certificate_voronoi_grouped
from cert_occ_voronoi_building_ftprnt
group by trading_as, geom;

--- filter to only alcohol-related restaurants
drop table certificate_voronoi_filtered;
select 
	issue_date,
	description_of_occupancy,
	occupancy_load,
	floors_occupied,
	trading_as,
	address,
	geom
into certificate_voronoi_filtered 
from certificate_voronoi_grouped
where lower(description_of_occupancy) ~ '(bar|restaurant|lounge|cocktail|tavern|cocktail|brewery|hotel|patio|food|historic)'
and lower(description_of_occupancy) !~ '(residential|coffee|barber|venue|manufacturing|grocery|wholesale|child|market|school|education|classroom|medical|residence|swimming|theater|lodging|transient|university|gallery|salon|studio|office|warehouse)'
or lower(description_of_occupancy) is null;	

-- For now, keep just the buildings that intersect with a bar
drop table if exists intersects;
	select
		distinct a.name,
		ogc_fid,
		a.osm_id,
		a.wkb_geometry,
		b.trading_as,
		b.issue_date,
		split_part(a.address,',',1) as address,
		split_part(b.address,',',1) as certificate_address,
		b.geom,
		lower(b.description_of_occupancy) as description,
		b.floors_occupied,
		b.occupancy_load,
		a.liquor_license,
		rank () over (partition by a.name order by levenshtein(split_part(lower(a.address),',',1),split_part(lower(b.address),',',1)), levenshtein(lower(a.name),lower(b.trading_as),1,0,1) asc)
	into intersects
	from 
		osm_bars a
	left outer join 
		certificate_voronoi_filtered b
	on ST_DWITHIN(a.wkb_geometry, b.geom,50)
	where 
	levenshtein(lower(a.name),lower(b.trading_as),1,0,1) <= 5;

drop table if exists grouped;
select 
	name,
	max(issue_date) as issue_date,
	max(floors_occupied) as floors_occupied,
	max(occupancy_load) as occupancy_load,
	max(description) as description_of_occupancy,
	max(address) as address,
	max(osm_id) as osm_id,
	liquor_license,
	wkb_geometry,
	geom
into grouped
from intersects
where rank = 1
group by name, geom, liquor_license, wkb_geometry
order by name;

alter table grouped add column sq_footage INT;
alter table grouped add column occupancy INT;
alter table grouped add column reverse_calc INT;
alter table grouped add column average_calc INT;


-- 
-- CALCULATIONS
--
update grouped set occupancy_load = null where occupancy_load='575     = 240 2ND FLOOR; 335 3RD FLOOR' or occupancy_load='113 (INSIDE)' or occupancy_load='8-12' or occupancy_load='0';
-- favor the official listed occupancy_load
update grouped set occupancy = occupancy_load::int where occupancy_load is not null;
-- take the area of the geometry, convert to square feet instead of meters
update grouped set sq_footage = (ST_area(geom)*10.764) where sq_footage is null;
-- account for just portions of buildings
update grouped set sq_footage = sq_footage/4 where floors_occupied ilike '%part%';
-- account for bars with multiple floors... assume some open-air spaces (ie, multiple of 1.5x instead of just 2x)
update grouped set sq_footage = sq_footage*1.5 where floors_occupied ilike '%,%' or floors_occupied ilike '%&%' or floors_occupied ilike '%AND%';
-- some SQ.Feet are just too large, based on total building footage, adjust
update grouped set sq_footage = 10000 where sq_footage > 10000 and name != 'DC Star';
-- calculate a rough occupancy
update grouped set occupancy = (sq_footage*.50)/15 where occupancy is null;
-- Wherever we do have occupancy numbers 
update grouped set reverse_calc = (occupancy*15)*2 where occupancy_load is not null;
-- Average the sq_footage vs. reverse_calc
update grouped set average_calc = (sq_footage+reverse_calc)/2 where reverse_calc is not null; 


-- add any 'missing' bars (assuming OSM bars is 'master' list)
insert into grouped(name, wkb_geometry)
	select 
		a.name, 
		a.wkb_geometry 
	from osm_bars a
	left join grouped b
	on a.name=b."name"
	where b."name" is null;

-- Calculate a rough square footage 
-- for those bars without building footprints attached
-- by: taking the average square footage of the nearest
-- 5 bars with square footage measurements

with nearest_neighbors as(
select 
	a.name as bar_name,
	sum(b.avg_sq_footage)/5 as sq_footage_of_nn
from grouped a
cross join lateral (
	select 
		b."name" as nearest_bar, 
		b.wkb_geometry as nearest_bar_geom, 
		b.average_calc as avg_sq_footage,
		a.wkb_geometry <-> b.wkb_geometry as dist
	from grouped b 
	where a.name != b.name
	and a.average_calc is null
	order by dist
	limit 5
) b 
group by a.name)
update grouped a
	set average_calc = sq_footage_of_nn
	from nearest_neighbors b
	where a.name = b.bar_name
	and a.average_calc is null;

update grouped set occupancy = (average_calc*.50)/15 where sq_footage is null;

-- Create final table
drop table if exists final;
create table final as
	select
		distinct on (name) name,
		average_calc as avg_sq_footage,
		occupancy,
		ST_X(st_transform(wkb_geometry,4326)) as X,
		ST_Y(st_transform(wkb_geometry,4326)) as Y,
		liquor_license
	from grouped;