TARGETS=bragi cosmogony2mimir ntfs2mimir openaddresses2mimir osm2mimir
DEPLOY_HOST=sober-cassini.webschuur.com

all:
	cargo build --release

deploy:
	for file in $(TARGETS); do scp ./target/release/$$file deploy@$(DEPLOY_HOST):/tmp/$$file && ssh deploy@$(DEPLOY_HOST) mv /tmp/$$file /usr/local/bin/$$file; done
	rsync --recursive scripts/ deploy@$(DEPLOY_HOST):/usr/share/mimirsbrunn/
	rsync ./poi_config.json deploy@$(DEPLOY_HOST):/etc/mimirsbrunn/
	ssh deploy@$(DEPLOY_HOST) sudo systemctl restart bragi.service

load:
	./scripts/import2mimir.sh
