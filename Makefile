include tools/mod.mk

# This repo's own targets and hooks go below. Document targets with "## text" so
# `make help` lists them; hooks use double colons (test-extra:: and so on, see tools/mod.mk).

build-plugin: ## Cook the Off Duty plugin (Linux kit) into src/OffDuty_Assets and record its inputs
	tools/build_plugin.sh $(ARGS)

simtest: ## Simulation tests through ZC Sandbox: make simtest ARGS='run --mission … ' (see tools/simtest.py)
	python3 tools/simtest.py $(ARGS)

sync-instances: ## Copy the scripts and paks into the simtest game copies (Instance N)
	tools/sync_instances.sh

package-extra:: ## (refuses paks that are stale against src/OffDuty_Assets/BUILD.sha256)
	@python3 tools/check_paks.py
