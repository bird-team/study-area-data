# Main instructions
## build data
all: data

# Individual commands
## clean data
clean:
	@rm -f exports/study-area.shp
	@rm -f exports/study-area.shx
	@rm -f exports/study-area.dbf
	@rm -f exports/study-area.prj

## make data
data:
	@docker run --name=bba -w /tmp -dt 'brisbanebirdteam/build-env:latest' \
	&& docker cp . bba:/tmp/ \
	&& docker exec bba sh -c "Rscript code/make-data.R" \
	&& docker cp bba:/tmp/exports/study-area.shp exports \
	&& docker cp bba:/tmp/exports/study-area.shx exports \
	&& docker cp bba:/tmp/exports/study-area.prj exports \
	&& docker cp bba:/tmp/exports/study-area.dbf exports || true
	@docker stop -t 1 bba || true && docker rm bba || true

# docker container commands
## pull image
pull_image:
	@docker pull 'brisbanebirdteam/build-env:latest'

## remove image
rm_image:
	@docker image rm 'brisbanebirdteam/build-env:latest'

## start container
start_container:
	@docker run --name=bba -w /tmp -dt 'brisbanebirdteam/build-env:latest'

## kill container
stop_container:
	@docker stop -t 1 bba || true && docker rm bba || true

# PHONY
.PHONY: data clean pull_image rm_image start_container stop_container
