#' Multiscale Deformable Attention
#'
#' Performs the multiscale deformable attention operation.
#'
#' @param value (Tensor) The input tensor values.
#' @param spatial_shapes (Tensor) The spatial shapes of the input feature maps.
#' @param level_start_index (Tensor) The starting index for each feature map level.
#' @param sampling_loc (Tensor) The sampling locations (offsets).
#' @param attn_weight (Tensor) The attention weights.
#' @param im2col_step (int) The im2col step size.
#'
#' @return A (Tensor) result of the forward pass.
#' @export
#' @useDynLib torchvisionlib, .registration = TRUE
#' @importFrom torch nn_module
ops_ms_deform_attn <- function(value, spatial_shapes, level_start_index, sampling_loc, attn_weight, im2col_step) {
  # makes `ms_deform_attn_forward_cpp` available as an R function.
  ms_deform_attn_forward_cpp(
    value,
    spatial_shapes,
    level_start_index,
    sampling_loc,
    attn_weight,
    im2col_step
  )
}
