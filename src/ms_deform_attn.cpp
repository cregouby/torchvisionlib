/*!
 **************************************************************************************************
 * {torch} bindings for Multiscale Deformable Attention
 *
 * This file provides the bindings to expose the ms_deform_attn::forward
 * and ms_deform_attn::backward functions to R
 *
 * The core logic is defined in 'ms_deform_attn.h' and the associated CUDA files.
 **************************************************************************************************
 */

#include <torch/torch.h>

#include "ms_deform_attn.h"

#ifdef WITH_CUDA
#include "cuda/ms_deform_attn_cuda.h"
#endif


//' Multiscale Deformable Attention Forward Pass
//'
//' @param value Input tensor (value)
//' @param spatial_shapes Input tensor (spatial_shapes)
//' @param level_start_index Input tensor (level_start_index)
//' @param sampling_loc Input tensor (sampling_loc)
//' @param attn_weight Input tensor (attn_weight)
//' @param im2col_step Integer (im2col_step)
//' @return Output tensor
//' @keywords internal

// [[Rcpp::export]]
torch::Tensor ms_deform_attn_forward_cpp(
   const torch::Tensor& value,
   const torch::Tensor& spatial_shapes,
   const torch::Tensor& level_start_index,
   const torch::Tensor& sampling_loc,
   const torch::Tensor& attn_weight,
   const int64_t im2col_step)
{
 // Call the C++ function from ms_deform_attn.h
 // Note: R integers are int64_t, but the C++ header expects int.
 return ms_deform_attn::forward(
   value,
   spatial_shapes,
   level_start_index,
   sampling_loc,
   attn_weight,
   (int)im2col_step
 );
}

//' Multiscale Deformable Attention Backward Pass
//'
//' @param value Input tensor (value)
//' @param spatial_shapes Input tensor (spatial_shapes)
//' @param level_start_index Input tensor (level_start_index)
//' @param sampling_loc Input tensor (sampling_loc)
//' @param attn_weight Input tensor (attn_weight)
//' @param grad_output Input tensor (grad_output)
//' @param im2col_step Integer (im2col_step)
//' @return A list of gradient tensors (grad_value, grad_sampling_loc, grad_attn_weight)
//' @keywords internal

// [[Rcpp::export]]
std::vector<torch::Tensor> ms_deform_attn_backward_cpp(
   const torch::Tensor& value,
   const torch::Tensor& spatial_shapes,
   const torch::Tensor& level_start_index,
   const torch::Tensor& sampling_loc,
   const torch::Tensor& attn_weight,
   const torch::Tensor& grad_output,
   const int64_t im2col_step)
{
 // Call the backward function from ms_deform_attn.h
 // Cast R's int64_t to the C++ function's expected int.
 std::vector<torch::Tensor> grads = ms_deform_attn::backward(
   value,
   spatial_shapes,
   level_start_index,
   sampling_loc,
   attn_weight,
   grad_output,
   (int)im2col_step
 );

 // {torchexport} will handle converting std::vector<torch::Tensor>
 // into an R List of torch_tensor objects.
 return grads;
}
