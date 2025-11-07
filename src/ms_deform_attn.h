/*!
 **************************************************************************
 * Modified from Balore (https://github.com/Balocre/ms_deform_attn/tree/master)
 **************************************************************************
 */

#pragma once

#include <torch/torch.h>

#ifdef WITH_CUDA
#include "cuda/ms_deform_attn_cuda.h"
#endif

namespace ms_deform_attn
{

torch::Tensor forward(
    const torch::Tensor &value,
    const torch::Tensor &spatial_shapes,
    const torch::Tensor &level_start_index,
    const torch::Tensor &sampling_loc,
    const torch::Tensor &attn_weight,
    const int im2col_step)
{
  if (value.is_cuda())
  {
#ifdef WITH_CUDA
    return forward_cuda(
      value, spatial_shapes, level_start_index, sampling_loc, attn_weight, im2col_step);
#else
    TORCH_CHECK(false, "Not compiled with GPU support");
#endif
  }
  TORCH_CHECK(false, "Not implemented on the CPU");
}

std::vector<torch::Tensor> backward(
    const torch::Tensor &value,
    const torch::Tensor &spatial_shapes,
    const torch::Tensor &level_start_index,
    const torch::Tensor &sampling_loc,
    const torch::Tensor &attn_weight,
    const torch::Tensor &grad_output,
    const int im2col_step)
{
  if (value.is_cuda())
  {
#ifdef WITH_CUDA
    return backward_cuda(
      value, spatial_shapes, level_start_index, sampling_loc, attn_weight, grad_output, im2col_step);
#else
    TORCH_CHECK(false, "Not compiled with GPU support");
#endif
  }
  TORCH_CHECK(false, "Not implemented on the CPU");
}

}
