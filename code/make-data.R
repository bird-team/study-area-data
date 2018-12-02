# Initialization
## set default options
options(stringsAsFactors = FALSE, error = function() {traceback();stop()})

## set parameters
resolution <- 500

## define functions
st_explode <- function(x) {
  if (inherits(x, "sf")) {
    ex <- lapply(sf::st_geometry(x), sf::st_sfc)
    ex <- lapply(ex, sf::st_cast, "POLYGON")
    ex <- lapply(seq_along(ex),
               function(i) sf::st_sf(id = rep(i, length(ex[[i]])),
                                     geometry = ex[[i]]))
    ex <- do.call(rbind, ex)
    pos <- ex$id
    ex <- sf::st_geometry(ex)
    d <- as.data.frame(x)
    d <- d[, which(names(d) != "geometry"), drop = FALSE]
    d <- d[pos, , drop = FALSE]
    d <- tibble::as_tibble(d)
    d$geometry <- ex
    ex <- sf::st_sf(d)
  } else {
    ex <- sf::st_cast(x, "POLYGON")
  }
  sf::st_set_crs(ex, sf::st_crs(x))
}

st_remove_slivers <- function(x) {
  x <- st_explode(x)
  if (inherits(x, "sfc"))
    return(x[as.numeric(sf::st_area(x)) > 0.1])
  return(x[as.numeric(sf::st_area(x)) > 0.1, ])
}

st_fast_difference <- function(x, y) {
  x <- sf::st_geometry(x)
  y <- sf::st_geometry(y)
  xu <- sf::st_union(x)
  sf::st_crs(xu) <- sf::st_crs(x)
  yu <- sf::st_union(y)
  sf::st_crs(yu) <- sf::st_crs(x)
  xe <- st_explode(x)
  sf::st_crs(xe) <- sf::st_crs(x)
  ye <- st_explode(y)
  sf::st_crs(ye) <- sf::st_crs(x)
  xi <- as.matrix(sf::st_intersects(xe, yu))[, 1]
  yi <- as.matrix(sf::st_intersects(ye, xu))[, 1]
  out <- sf::st_difference(xe[xi], sf::st_union(ye[yi]))
  out <- append(xe[!xi], out)
  out
}

blank_raster <- function (x, res) {
  assertthat::assert_that(inherits(x, "Spatial"), is.numeric(res),
    all(is.finite(res)), length(res) %in% c(1, 2))
  if (length(res) == 1)
    res <- c(res, res)
  if ((raster::xmax(x) - raster::xmin(x)) <= res[1]) {
    xpos <- c(raster::xmin(x), res[1])
  }
  else {
    xpos <- seq(raster::xmin(x), raster::xmax(x) + (res[1] *
      (((raster::xmax(x) - raster::xmin(x))%%res[1]) !=
         0)), res[1])
  }
  if ((raster::ymax(x) - raster::ymin(x)) <= res[2]) {
    ypos <- c(raster::ymin(x), res[2])
  }
  else {
    ypos <- seq(raster::ymin(x), raster::ymax(x) + (res[2] *
      (((raster::ymax(x) - raster::ymin(x))%%res[2]) !=
        0)), res[2])
  }
  rast <- raster::raster(xmn = min(xpos), xmx = max(xpos),
    ymn = min(ypos), ymx = max(ypos), nrow = length(ypos) -
      1, ncol = length(xpos) - 1)
  return(raster::setValues(rast, 1))
}

## create temporary directories
tmp1 <- file.path(tempdir(), basename(tempfile(fileext = "")))
dir.create(tmp1, showWarnings = FALSE, recursive = TRUE)

## set parameters
unzip(dir("data/land", "^.*\\.zip$", full.names = TRUE),
          exdir = tmp1)
raw_path <- dir(tmp1, "^.*\\.shp$", full.names = TRUE)[1]

## load packages
library(dplyr)
library(sf)

# Preliminary processing
## load and data
raw_data <- sf::st_read(raw_path)

## clean spatial data
raw_data <- raw_data %>%
            sf::st_transform(3857) %>%
            sf::st_set_precision(1000) %>%
            lwgeom::st_make_valid() %>%
            sf::st_buffer(0) %>%
            lwgeom::st_snap_to_grid(1) %>%
            filter(!sf::st_is_empty(.)) %>%
            lwgeom::st_make_valid() %>%
            sf::st_collection_extract(type = "POLYGON") %>%
            filter(grepl("Queensland", STE_NAME16))

# Main processing
## dissolve data to get terrestrial land mass
land_data <- sf::st_union(raw_data)

## extract Brisbane data
study_area_data <- raw_data %>%
                   filter(grepl("Brisbane", LGA_NAME16)) %>%
                   sf::st_union() %>%
                   lwgeom::st_make_valid() %>%
                   sf::st_collection_extract(type = "POLYGON")

## extract outside study area data
outside_data <- study_area_data %>%
                sf::st_buffer(units::set_units(1.852 * 200, km)) %>%
                sf::st_intersects(raw_data) %>%
                as.matrix() %>%
                c()
outside_data <- raw_data[outside_data, ]
outside_data <- outside_data %>%
                filter(!grepl("Brisbane", LGA_NAME16))

## identify marine areas within Brisbane LGA's EEZ (200 nautical miles)
marine_data <- study_area_data %>%
               sf::st_buffer(units::set_units(1.852 * 200, km)) %>%
               sf::st_difference(land_data) %>%
               sf::st_sf()

## create grid over buffer data
marine_data$value <- 1
grid_data <- blank_raster(as(marine_data, "Spatial"), resolution)
grid_data <- raster::rasterize(as(marine_data, "Spatial"), grid_data,
                               field = "value")

## convert grid data to points
grid_point_data <- raster::as.data.frame(grid_data, xy = TRUE,
                                         na.rm = TRUE)[, seq_len(2)]

## convert study area to points
study_area_point_data <- study_area_data %>%
                         sf::st_sf() %>%
                         as("Spatial") %>%
                         ggplot2::fortify() %>%
                         dplyr::select(long, lat) %>%
                         dplyr::rename(x = long, y = lat) %>%
                         as.matrix()

## convert outside area to points
outside_area_point_data <- outside_data %>%
                           sf::st_sf() %>%
                           as("Spatial") %>%
                           ggplot2::fortify() %>%
                           dplyr::select(long, lat) %>%
                           dplyr::rename(x = long, y = lat) %>%
                           as.matrix()

## calculate distances between points and study area, other area
study_area_dists <- FNN::get.knnx(study_area_point_data, grid_point_data, k = 1)
other_area_dists <- FNN::get.knnx(outside_area_point_data, grid_point_data,
                                  k = 1)

## find which grid cells are closest to study area
subset_points <- grid_point_data[study_area_dists$nn.dist[, 1] <=
                                 other_area_dists$nn.dist[, 1], ]

## remove any points that overlap with the study area
overlap_pos <- subset_points %>%
               sp::SpatialPoints() %>%
               as("sf") %>%
               sf::st_set_crs(3857) %>%
               sf::st_intersects(study_area_data) %>%
               as.matrix() %>%
               c()
subset_points <- subset_points[!overlap_pos, ]

## merge grid cells together
subset_cells <- raster::extract(grid_data, subset_points,
                                cellnumbers = TRUE)[, 1]
grid_data2 <- grid_data
grid_data2[] <- NA
grid_data2[subset_cells] <- 1
close_grid_data <- raster::rasterToPolygons(grid_data2, dissolve = TRUE) %>%
                   as("sf") %>%
                   sf::st_set_crs(3857) %>%
                   sf::st_union() %>%
                   lwgeom::st_make_valid() %>%
                   smoothr::smooth(method = "ksmooth", smoothness = 5) %>%
                   sf::st_buffer(100) %>%
                   sf::st_difference(study_area_data) %>%
                   lwgeom::st_make_valid()

## add in geometries for river and places near shore
missing_data <- study_area_data %>%
                sf::st_buffer(1000) %>%
                sf::st_difference(land_data) %>%
                lwgeom::st_make_valid() %>%
                as("Spatial") %>%
                sp::disaggregate() %>%
                as("sf") %>%
                sf::st_set_crs(3857)
missing_pos <- missing_data %>%
               st_buffer(10) %>%
               st_intersects(land_data %>%
                             sf::st_geometry() %>%
                             st_explode() %>%
                             sf::st_sf() %>%
                             mutate(area = sf::st_area(.)) %>%
                             arrange(desc(area)) %>%
                             filter(row_number() == 1) %>%
                             sf::st_geometry() %>%
                             sf::st_set_crs(3857)) %>%
               as.matrix() %>%
               c()
missing_data <- missing_data[missing_pos, ]
missing_data <- missing_data %>%
                mutate(area = as.numeric(sf::st_area(.))) %>%
                arrange(desc(area)) %>%
                filter(row_number() == 1) %>%
                sf::st_union() %>%
                sf::st_difference(study_area_data)

## merge missing areas with main geometry
close_grid_data <- close_grid_data %>%
                   append(missing_data) %>%
                   sf::st_union() %>%
                   sf::st_difference(study_area_data)

# Exports
## save data set
export_data <- sf::st_sf(name = c("land", "marine"),
                         geometry = append(study_area_data, close_grid_data))
sf::write_sf(export_data, "exports/study-area.shp", delete_layer = TRUE)
