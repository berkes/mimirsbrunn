TARGETS=bragi cosmogony2mimir ntfs2mimir openaddresses2mimir osm2mimir
DEPLOY_HOST=sober-cassini.webschuur.com

all:
	cargo build --release

deploy:
	## TODO: find a trick to overwrite a running binary without downtime
	## Probably something with symlinks and versioned bin files.
	for file in $(TARGETS); do scp target/release/$$file deploy@$(DEPLOY_HOST):/usr/local/bin/$$file; done
	rsync --recursive scripts/ deploy@$(DEPLOY_HOST):/usr/share/mimirsbrunn/
	rsync ./poi_config.json deploy@$(DEPLOY_HOST):/etc/mimirsbrunn/

load:
	./scripts/import2mimir.sh
