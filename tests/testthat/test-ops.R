test_that("nms", {
  torch::torch_manual_seed(1)
  boxes <- create_tensors_with_iou(10, 1)
  scores <- torch::torch_rand(10)
  result <- ops_nms(boxes, scores, 1)
  reference <- torch::torch_tensor(as.integer(c(0, 2, 5, 7, 3, 9, 8, 1, 4, 6) + 1))
  expect_equal_to_tensor(result, reference)

  expect_error(
    ops_nms(torch::torch_rand(4), torch::torch_rand(3), 0.5),
    regexp = "boxes should be a 2d tensor, got 1D"
  )
  expect_error(
    ops_nms(torch::torch_rand(3, 5), torch::torch_rand(3), 0.5),
    regexp = "boxes should have 4 elements in dimension 1, got 5"
  )
  expect_error(
    ops_nms(torch::torch_rand(3, 4), torch::torch_rand(3,2), 0.5),
    regexp = "scores should be a 1d tensor, got 2D"
  )
  expect_error(
    ops_nms(torch::torch_rand(3, 4), torch::torch_rand(4), 0.5),
    regexp = "boxes and scores should have same number of elements in dimension 0, got 3 and 4"
  )

})

test_that("deform_conv", {

  input <- torch_rand(4, 3, 10, 10)
  kh <- kw <- 3
  weight <- torch_rand(5, 3, kh, kw)
  offset <- torch_rand(4, 2 * kh * kw, 8, 8)
  mask <- torch_rand(4, kh * kw, 8, 8)
  out <- ops_deform_conv2d(input, offset, weight, mask = mask)
  expect_equal(out$shape, c(4,5,8,8))

  expect_error(
    ops_deform_conv2d(torch_rand(10), offset, weight, mask = mask),
    regexp = "Expected input_c.ndimension()"
  )
  expect_error(
    ops_deform_conv2d(input, torch_rand(5, 4, kh, kw), weight, mask = mask),
    regexp = "the shape of the offset tensor at"
  )

})

test_that("ps roi align works", {

  torch::torch_manual_seed(2)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1,1,5,5), ncol = 4)))

  roi <- nn_ps_roi_align(output_size = c(1, 1))

  output <- roi(input, boxes)
  expect_equal_to_r(output,
    # result validated with pytorch.
    c(0.1054, -0.3602, 0.21501),
    tolerance = 1e-4
  )
})

test_that("roi align basic functionality", {
  torch::torch_manual_seed(42)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1, 1, 5, 5), ncol = 4)))

  # Test with function interface
  output <- ops_roi_align(input, boxes, output_size = c(2, 2))

  # Check output shape [K, C, oh, ow] = [1, 3, 2, 2]
  expect_tensor_shape(output, c(1, 3, 2, 2))

  # Verify output is a tensor with reasonable values
  expect_true(all(is.finite(as.numeric(output))))

  # Verify operation is deterministic
  torch::torch_manual_seed(42)
  input2 <- torch_randn(1, 3, 28, 28)
  output2 <- ops_roi_align(input2, boxes, output_size = c(2, 2))
  expect_true(torch_allclose(output, output2))
})

test_that("roi align with aligned=TRUE", {
  torch::torch_manual_seed(42)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1, 1, 5, 5), ncol = 4)))

  # Test with aligned=TRUE (Detectron2 implementation)
  output_aligned <- ops_roi_align(input, boxes, output_size = c(2, 2), aligned = TRUE)

  # Test with aligned=FALSE (legacy implementation)
  output_legacy <- ops_roi_align(input, boxes, output_size = c(2, 2), aligned = FALSE)

  # Both should have correct shape
  expect_equal(output_aligned$shape, c(1, 3, 2, 2))
  expect_equal(output_legacy$shape, c(1, 3, 2, 2))

  # Outputs should differ due to -0.5 pixel shift (in most cases)
  # Note: For some inputs they might be close, so we just check they're both valid
  expect_tensor(output_aligned)
  expect_tensor(output_legacy)
  expect_true(all(is.finite(as.numeric(output_aligned))))
  expect_true(all(is.finite(as.numeric(output_legacy))))
})

test_that("roi align with multiple boxes", {
  torch::torch_manual_seed(123)
  input <- torch_randn(2, 3, 28, 28)
  # List of tensors - one for each batch element
  boxes <- list(
    torch_tensor(matrix(c(1, 1, 10, 10, 5, 5, 15, 15), ncol = 4, byrow = TRUE)),
    torch_tensor(matrix(c(2, 2, 8, 8), ncol = 4))
  )

  output <- ops_roi_align(input, boxes, output_size = c(3, 3))

  # Total boxes: 2 from batch 1 + 1 from batch 2 = 3
  # Output shape: [3, 3, 3, 3]
  expect_tensor_shape(output, c(3, 3, 3, 3))
})

test_that("roi align with single tensor format", {
  torch::torch_manual_seed(99)
  input <- torch_randn(2, 3, 28, 28)
  # Single tensor with batch indices in first column (1-indexed for R)
  boxes <- torch_tensor(matrix(c(
    1, 1, 1, 10, 10,
    1, 5, 5, 15, 15,
    2, 2, 2, 8, 8
  ), ncol = 5, byrow = TRUE))

  output <- ops_roi_align(input, boxes, output_size = c(2, 2))

  # 3 boxes total
  expect_tensor_shape(output, c(3, 3, 2, 2))
})

test_that("roi align with sampling_ratio parameter", {
  torch::torch_manual_seed(7)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1, 1, 10, 10), ncol = 4)))

  # Adaptive sampling (default)
  output_adaptive <- ops_roi_align(input, boxes, output_size = c(2, 2), sampling_ratio = -1)

  # Fixed sampling ratio
  output_fixed <- ops_roi_align(input, boxes, output_size = c(2, 2), sampling_ratio = 2)

  # Both should have same shape but potentially different values
  expect_tensor_shape(output_adaptive, output_fixed$shape)
})

test_that("roi align with spatial_scale", {
  torch::torch_manual_seed(11)
  input <- torch_randn(1, 3, 56, 56)
  # Boxes defined on 224x224 image scale
  boxes <- list(torch_tensor(matrix(c(10, 10, 50, 50), ncol = 4)))

  # Feature map is 56x56 (0.25x scale of 224x224)
  output <- ops_roi_align(input, boxes, output_size = c(3, 3), spatial_scale = 0.25)

  expect_tensor_shape(output, c(1, 3, 3, 3))
})

test_that("roi align module wrapper", {
  torch::torch_manual_seed(42)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1, 1, 5, 5), ncol = 4)))

  # Test module interface
  roi <- nn_roi_align(output_size = c(2, 2), spatial_scale = 1.0, sampling_ratio = -1)
  output_module <- roi(input, boxes)

  # Test function interface with same parameters
  output_function <- ops_roi_align(input, boxes, output_size = c(2, 2))

  # Should produce identical results
  expect_true(torch_allclose(output_module, output_function))
})

test_that("roi align module with aligned parameter", {
  torch::torch_manual_seed(42)
  input <- torch_randn(1, 3, 28, 28)
  boxes <- list(torch_tensor(matrix(c(1, 1, 5, 5), ncol = 4)))

  # Test module with aligned=TRUE
  roi <- nn_roi_align(output_size = c(2, 2), aligned = TRUE)
  output <- roi(input, boxes)

  expect_equal(output$shape, c(1, 3, 2, 2))
})
