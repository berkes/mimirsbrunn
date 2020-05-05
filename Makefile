TARGETS=bragi cosmogony2mimir ntfs2mimir openaddresses2mimir osm2mimir
DEPLOY_HOST=sober-cassini.webschuur.com
DEPLOY_TO=
OSM_FILE=/mnt/sda/OSM/test-data/gelderland-latest.osm.pbf
OA_FILE=/mnt/sda/OSM/openaddr/nl/countrywide.csv
DATASET="nl"

all:
	cargo build --release

deploy:
	## TODO: find a trick to overwrite a running binary without downtime
	## Probably something with symlinks and versioned bin files.
	for file in $(TARGETS); do scp target/release/$$file deploy@$(DEPLOY_HOST):/usr/local/bin/; done

load:
	./scripts/import2mimir.sh
