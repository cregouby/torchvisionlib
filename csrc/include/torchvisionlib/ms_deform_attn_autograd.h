#pragma once
#include <torch/torch.h>

#ifndef MS_DEFORM_ATTN_AUTOGRAD_H
#define MS_DEFORM_ATTN_AUTOGRAD_H

// Declaration of the autograd function
struct MSDeformAttnFunction : torch::autograd::Function<MSDeformAttnFunction> {
  public:
    static torch::Tensor forward(
      torch::autograd::AutogradContext* ctx,
      const torch::Tensor& value,
      const torch::Tensor& spatial_shapes,
      const torch::Tensor& level_start_index,
      const torch::Tensor& sampling_loc,
      const torch::Tensor& attn_weight,
      const int im2col_step
  );

    static torch::autograd::tensor_list backward(
        torch::autograd::AutogradContext *ctx,
        torch::autograd::variable_list grad_output);
};

// Public interface function
torch::Tensor multiscale_deformable_attn(
    const torch::Tensor& value,
    const torch::Tensor& spatial_shapes,
    const torch::Tensor& level_start_index,
    const torch::Tensor& sampling_loc,
    const torch::Tensor& attn_weight,
    const int im2col_step = 1
);

#endif // MS_DEFORM_ATTN_AUTOGRAD_H
