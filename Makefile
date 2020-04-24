TARGETS=bragi cosmogony2mimir openaddresses2mimir osm2mimir
DEPLOY_TO=
OSM_FILE=/mnt/sda/OSM/test-data/gelderland-latest.osm.pbf
OA_FILE=/mnt/sda/OSM/openaddr/nl/countrywide.csv
DATASET="nl"

all:
	cargo build --release

deploy:
	for file in $(TARGETS); do scp target/release/$$file deploy@romantic-wilson.placebazaar.org:/usr/local/oot/bin/; done

load: download load_admins load_addresses load_osm_streets load_pois

download:
	# noop: TODO

load_admins:
	# TODO: load cosmogony instead?
	cargo run --bin osm2mimir -- --input $(OSM_FILE) --dataset $(DATASET) --level 8 --import-admin

load_addresses:
	cargo run --bin openaddresses2mimir -- --input $(OA_FILE) --dataset $(DATASET)

load_osm_streets:
	cargo run --bin osm2mimir -- --input $(OSM_FILE) --dataset $(DATASET) --import-way

load_pois:
	cargo run --bin osm2mimir -- --input $(OSM_FILE) --dataset $(DATASET) --poi-config poi_config.json --import-poi
