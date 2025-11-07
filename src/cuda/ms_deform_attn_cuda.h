/*!
 **************************************************************************
 * Modified from Balore (https://github.com/Balocre/ms_deform_attn/tree/master)
 **************************************************************************
 */

#pragma once
#include <torch/torch.h>

  namespace ms_deform_attn
  {

  torch::Tensor forward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const int im2col_step);

  std::vector<torch::Tensor> backward_cuda(
      const torch::Tensor &value,
      const torch::Tensor &spatial_shapes,
      const torch::Tensor &level_start_index,
      const torch::Tensor &sampling_loc,
      const torch::Tensor &attn_weight,
      const torch::Tensor &grad_output,
      const int im2col_step);

  }
