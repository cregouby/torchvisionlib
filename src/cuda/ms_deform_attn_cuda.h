/*!
 **************************************************************************
 * Modified from Balore (https://github.com/Balocre/ms_deform_attn/tree/master)
 **************************************************************************
 */

#pragma once
#include <torch/torch.h>

// avoid name mangling
extern "C" {
  torch::Tensor ms_deform_attn_forward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const int im2col_step);

  std::vector<torch::Tensor> ms_deform_attn_backward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const torch::Tensor &grad_output,
      const int im2col_step);
}

namespace ms_deform_attn {
  torch::Tensor forward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const int im2col_step)
  {
          return ms_deform_attn_forward_cuda(value, spatial_shapes, level_start_index, sampling_loc, attn_weight, im2col_step);
  }

  std::vector<torch::Tensor> backward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const torch::Tensor &grad_output,
      const int im2col_step)
  {
        return ms_deform_attn_backward_cuda(value, spatial_shapes, level_start_index, sampling_loc, attn_weight, grad_output, im2col_step);
  }

}
