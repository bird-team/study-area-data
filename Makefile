# Main instructions
## build data
all: data

# Define variables
ifdef ComSpec
	RM=del /F /Q
	RMDIR=rmdir
	PATHSEP2=\\
	MV=MOVE
else
	RM=rm -f
	RMDIR=rm -rf
	PATHSEP2=/
	MV=mv
endif

# Individual commands
## clean data
clean:
	@$(RM) exports/study-area-data.shp
	@$(RM) exports/study-area-data.shx
	@$(RM) exports/study-area-data.dbf
	@$(RM) exports/study-area-data.prj

## make data
data:
	@docker run --name=bba -w /tmp -dt 'brisbanebirdteam/build-env:latest' \
	&& docker cp . bba:/tmp/ \
	&& docker exec bba sh -c "Rscript code/make-data.R" \
	&& docker cp bba:/tmp/exports/study-area-data.shp exports \
	&& docker cp bba:/tmp/exports/study-area-data.shx exports \
	&& docker cp bba:/tmp/exports/study-area-data.prj exports \
	&& docker cp bba:/tmp/exports/study-area-data.dbf exports || true
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
