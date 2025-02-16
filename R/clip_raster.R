
#====================
#geotranformation
#====================

geotransform <- function(geo_info,shape){
  m_geo_scale = matrix(c(geo_info[6],0,0, -geo_info[7]),ncol = 2, nrow = 2)
  lefuppercoord_x = geo_info[4]
  lefuppercoord_y = geo_info[5] + geo_info[6]*geo_info[1]
  m_geo_origin = matrix(c(lefuppercoord_x, lefuppercoord_y), nrow = 2, ncol = 1)

  coord_shape_leftupper = matrix(c(st_bbox(shape)[1],st_bbox(shape)[4]), nrow = 2, ncol = 1)
  coord_shape_rightlower = matrix(c(st_bbox(shape)[3],st_bbox(shape)[2]), nrow = 2, ncol = 1)

  m_geo_origin_trans = solve(m_geo_scale) %*% m_geo_origin
  pixel_left_upper = as.integer((solve(m_geo_scale)%*%coord_shape_leftupper) - m_geo_origin_trans)
  pixel_right_lower = as.integer((solve(m_geo_scale)%*%coord_shape_rightlower) - m_geo_origin_trans)

  xcount = abs(pixel_left_upper[1] - pixel_right_lower[1]) + 1
  ycount = abs(pixel_left_upper[2] - pixel_right_lower[2]) + 1

  #coord for clip raster
  coord_pixel_left_upper = m_geo_scale %*% pixel_left_upper + m_geo_origin
  x_max = coord_pixel_left_upper[1] + (xcount)*geo_info[6]
  y_min = coord_pixel_left_upper[2] - (ycount)*geo_info[7]
  bbox_sraster = c(coord_pixel_left_upper[1], y_min, x_max, coord_pixel_left_upper[2])
  names(bbox_sraster) = c("xmin","ymin","xmax","ymax")

  result = list()
  result[["offs"]] = c(pixel_left_upper[2], pixel_left_upper[1])
  result[["xcount"]] = xcount
  result[["ycount"]] = ycount
  result[["bbox"]] = bbox_sraster

  return(result)
}


#===============================
#Importing image
#===============================
#For this example we call only one image
library(rgdal)

function_time_name <- function(x){
  path_split = unlist(strsplit(x,'\\',fixed=TRUE))
  name_tif = path_split[length(path_split)]
  args_tiff = unlist(strsplit(name_tif,'-',fixed=TRUE))[1]
  date_split_tiff = unlist(strsplit(args_tiff,'_',fixed=TRUE))
  date_tiff = date_split_tiff[length(date_split_tiff)]
  year = substr(date_tiff,1,4)
  month = substr(date_tiff,5,6)
  day = substr(date_tiff,7,8)
  d <- as.Date(paste0(year,"-",month,"-",day), format="%Y-%m-%d")
  return(d)
}


#================================
#reading raster
#================================

read_raster <-function(files_raster, xyoffs, reg, r_shape_array, shape,names_bands){
  # files_raster: vector with raster paths
  list_composites = list()
  n_img = length(files_raster)
  l = 1
  pb = txtProgressBar(min = 0, max = n_img,style = 3)
  time_names_img = NULL
  for(j in files_raster){
    geo_info = rgdal::GDALinfo(j,returnStats = FALSE)
    datasource = rgdal::GDAL.open(j)
    list_bands = list()
    for(i in 1:geo_info[3]){
      band = names_bands[i]
      clip_extent = rgdal::getRasterData(datasource, offset = xyoffs, region.dim = reg, band=i)
      list_bands[[band]] = clip_extent * r_shape_array
    }
    time_name_img = as.character(function_time_name(j))
    list_composites[[time_name_img]] = array(unlist(list_bands),dim = c(reg[2], reg[1] , length(list_bands)))
    time_names_img = c(time_names_img,time_name_img)
    rgdal::closeDataset(datasource)
    Sys.sleep(0.1)
    setTxtProgressBar(pb,l)
    l = l + 1
  }
  result = list()
  result[["object"]] = shape$OBJECTI
  result[["bands"]] <- names_bands
  result[["data"]] <- list_composites
  result[["time"]] <- time_names_img
  result[["nrows"]] <- reg[1]
  result[["ncols"]] <- reg[2]
  return(result)
}


#crating sraster function
as_sraster <- function(shape,files_raster,names_bands){

  #shape
  cat(paste0("\tShape ",shape$OBJECTI),"\n")
  geo_info = rgdal::GDALinfo(files_raster[1],returnStats = FALSE)
  coord_pixel = geotransform(geo_info, shape)
  xyoffs = coord_pixel$offs
  nrows = coord_pixel$ycount
  ncols = coord_pixel$xcount
  reg = c(nrows,ncols)

  #Rasterize
  r <- stars::st_as_stars(st_bbox(coord_pixel$bbox) , nx = ncols, ny = nrows )
  shape$field = 1
  r_shape = stars::st_rasterize(shape[,"field"], r,options = "ALL_TOUCHED=TRUE")
  r_shape$field[r_shape$field == 0] = NA
  r_shape_array = r_shape$field

  result <- read_raster(files_raster, xyoffs, reg, r_shape_array,shape, names_bands)

  #Coordinates

  x_min = coord_pixel$bbox[1] + geo_info[6]/2
  y_min = coord_pixel$bbox[2] + geo_info[7]/2
  x_max = coord_pixel$bbox[3] - geo_info[6]/2
  y_max = coord_pixel$bbox[4] - geo_info[7]/2

  x_line = seq(x_min,x_max,geo_info[6])
  y_line = seq(y_max,y_min,-geo_info[7])
  coord_x_matrix = array(rep(x_line, ncols),dim = c(ncols, nrows))
  coord_y_matrix = t(array(rep(y_line, nrows),dim = c(nrows, ncols)))

  x_coordinates = data.frame(x=c(coord_x_matrix), y=c(coord_y_matrix))
  result$coordinates = x_coordinates
  result$label = as.character(shape$Legend)

  class(result) <- "sraster"
  return(result)
}


print.sraster <-
  function(x,...){
    cat("class:    sraster", "\n")
    cat("Object: ", x$object , "\n")
    cat("Label: ", x$label , "\n")
    cat("space dimension: nrows: ", x$nrows, " nccols: ", x$ncols,"\n")
    cat("Number of images: ", length(x$time) ,"\n")
    cat("Number of bands: ", length(x$bands),"\n")
    cat("Coord Origin x: ", x$coordinates[1,1]," and y: ", x$coordinates[1,2]  ,"\n")
  }


#===============================
#Clip sraster
#===============================

clip_sraster = function(x, mask, type, threshold = 0.5 ){
  if(type == 'Majority rule'){
    largest_cluster = order(table(mask),decreasing = TRUE)[1]
    mask[mask != largest_cluster] <- NA
    mask[mask == largest_cluster] <- 1
  }
  else if(type == 'No rule' ){
    mask[!is.na(mask)] <- 1
  }
  else if(type == 'rule_ndvi_water'){
    col_ndvi = grep("NDVI",x$bands)
    ndvi_layers = lapply(x$data,function(w,col_ndvi) w[,,col_ndvi],col_ndvi)
    clusters_name = names(table(mask))
    medians_clusters = NULL
    for(i in clusters_name){
      index = which(mask == i)
      list_values_index = lapply(ndvi_layers, function(w, index) as.numeric(w)[index], index)
      median_vector_index = median(unlist(list_values_index),na.rm=TRUE)
      medians_clusters = c(medians_clusters, median_vector_index)
    }
    query_cluster = order(medians_clusters,decreasing = FALSE)[1]
    mask[mask != query_cluster] <- NA
    mask[mask == query_cluster] <- 1
  }
  else if(type == 'rule_ndvi_wood'){
    #here the idea is to select the cluster with the largest NDVI
    col_ndvi = grep("NDVI",x$bands)
    ndvi_layers = lapply(x$data,function(w,col_ndvi) w[,,col_ndvi],col_ndvi)
    clusters_name = names(table(mask))
    medians_clusters = NULL
    for(i in clusters_name){
      index = which(mask == i)
      list_values_index = lapply(ndvi_layers, function(w, index) as.numeric(w)[index], index)
      median_vector_index = median(unlist(list_values_index),na.rm=TRUE)
      medians_clusters = c(medians_clusters, median_vector_index)
    }
    query_cluster = order(medians_clusters,decreasing = TRUE)[1]
    mask[mask != query_cluster] <- NA
    mask[mask == query_cluster] <- 1
  }
  else{
    stop("provide one of the methods")
  }

  func_mask <- function(y, mask) list(y * mask)

  for(tr in x$time)
  {
    array_clip_list = apply(x$data[[tr]], 3, func_mask,mask)
    array_clip_list = lapply(array_clip_list, "[[", 1)
    array_clip = array(unlist(array_clip_list),dim = dim(x$data[[tr]]))
    x$data[[tr]] <- array_clip
  }
  return(x)
}


#===============================
#as array
#===============================

as.array.sraster <-
  function(x,...)
  {
    n_rows = x$nrows
    n_cols = x$ncols
    n_layers = length(x$time) * length(x$bands)
    array_data = array(unlist(x$data), dim = c(n_cols, n_rows, n_layers))
    return(array_data)
  }

#===============================
#as data frame sf
#===============================

as.data.frame.sraster <-
  function(x,...)
  {
    array_x = as.array(x)
    data_2d = apply(array_x,3,convert_2d)
    index_nonan = apply(data_2d,1,func_nan)

    data_2d_nonan = data_2d[!index_nonan,]
    coordxy = x$coordinates[!index_nonan,]
    df_data_2d_nonan = data.frame(x$object, x$label,coordxy, matrix(data_2d_nonan,nrow = dim(coordxy)[1]))
    #names
    vector_names = NULL
    for(i in x$time){
      vector_name = lapply(x$bands,function(y,i){paste0(i,"-",y)}, i)
      vector_names = c(vector_names, unlist(vector_name))
    }

    colnames(df_data_2d_nonan) <- c("Object","Label","x","y",vector_names)

    df_spatial = st_as_sf(df_data_2d_nonan, coords = c("x","y"))
    return(df_spatial)
  }



funct_plot<- function(x){
  a = apply(x,1,rev)
  b = apply(a,2,rev)
  return(raster(b))
}

#===============================
#Clustering
#===============================
library(reshape2)

convert_2d <- function(x){
  y = reshape2::melt(x)
  return(y[,3])
}

func_nan <- function(x){all(is.na(x))}

library(fpc)

kmeans_sraster <-
  function(x,...)
  {
    array_sr = as.array(x)

    data_2d = apply(array_sr,3,convert_2d)

    index_nonan = apply(data_2d,1,func_nan)
    data_2d_nonan = data_2d[!index_nonan,]
    #I need to improve the following
    data_2d_nonan[is.na(data_2d_nonan)] <- 999999

    #defining number of clusters
    a = c(1:5)
    for(l in 2:6){
      km <- kmeans(data_2d_nonan,l)
      a[l-1] = round(fpc::calinhara(data_2d_nonan,clustering = km$cluster, cn = l),digits=2)
    }
    centers = order(a,decreasing = TRUE)[1] + 1
    cluster_data_2d = kmeans(data_2d_nonan,centers)

    vector_cluster = c(array(NA, dim = dim(array_sr)[1:2]))

    vector_cluster[!index_nonan]<-cluster_data_2d$cluster

    matrix_cluster = array(vector_cluster, dim = dim(array_sr)[1:2])
    return(matrix_cluster)
  }



#=======================================
#workflow_bhattacharyya
#=======================================

workflow_bhattacharyya = function(x, mean_a, cov_a){
  mean_b = apply(x[,-1],2,mean_vector)
  cov_b = cov(x[,-1],use = 'na.or.complete')
  #Bhattacharyya distance between a and b distribution
  dist_batha = bhattacharyya.dist(mean_a, mean_b, cov_a, cov_b)
  name_polygon = x[1,1]
  result_dist = c(name_polygon,dist_batha)
  return(result_dist)
}

mean_vector = function(x) mean(x,na.rm=TRUE)

b_distance <- function(y, prob){
  #y data frame with the especral and temporal information
  #prob percentage of information reteined into the analysis

  #mean and covariance matrix for all the samples
  mean_a = apply(y[,-1],2,mean_vector)
  cov_a = cov(y[,-1],use = 'na.or.complete')

  list_data_polygon = split(y,y$Object)

  distances_bhattacharyya = lapply(list_data_polygon, workflow_bhattacharyya, mean_a, cov_a)

  distance_bhattacharyya_df = do.call("rbind",distances_bhattacharyya)

  quantile_x = quantile(distance_bhattacharyya_df[,2] ,probs = c(prob),na.rm = TRUE)

  selected_polygon_names = distance_bhattacharyya_df[distance_bhattacharyya_df[,2]<=quantile_x &
                                                       !is.na(distance_bhattacharyya_df[,2]),1]

  return(selected_polygon_names)

}

#====================================
#stacking sraster objects
#====================================

stack <- function(x){
  base_layer = x[[1]]

  for(l in 1:(length(x)-1)){
    new_layer = x[[l+1]]
    stopifnot(class(base_layer) == 'sraster', class(new_layer) == 'sraster')
    time_new_layer = new_layer$time
    time_base_layer = base_layer$time
    stopifnot(all(time_base_layer == time_new_layer))
    n_rows = base_layer$nrows
    n_cols = base_layer$ncols
    n_bands_base_layer = length(base_layer$bands)
    n_bands_new_layer = length(new_layer$bands)

    #merging arrays
    data_base_new = list()
    for(k in time_base_layer){
      vector_base_new = c(as.numeric(base_layer$data[[k]]),new_layer$data[[k]])
      data_base_new[[k]] = array(vector_base_new, dim = c(n_cols,n_rows, n_bands_base_layer + n_bands_new_layer))
    }

    result[["object"]] = base_layer$object
    result[["bands"]] <- c(base_layer$bands, new_layer$bands)
    result[["data"]] <- data_base_new
    result[["time"]] <- c(base_layer$time)
    result[["nrows"]] <- base_layer$nrows
    result[["ncols"]] <- base_layer$ncols
    result[["coordinates"]] = base_layer$coordinates
    class(result) <- "sraster"
    base_layer = result
    }
  return(base_layer)
}





