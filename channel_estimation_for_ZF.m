function [delay_taps, Doppler_taps, chan_coef, taps, m_p_est, n_p_est,sigma_est] = ...
         channel_estimation_for_ZF(y, m_p, n_p, m_max, n_max, x_p, threshold_ratio)
    [N,M] = size(y);
    % 计算保护区边界
    % row_start = 1;
    % row_end   = N;
    col_start = max(1, m_p);
    col_end   = min(M, m_p + m_max);
    row_start = max(1, n_p - n_max);
    row_end   = min(N, n_p + n_max);
    % col_start = 1;
    % col_end   = M;

    % 提取导频区域
    y_region = y(row_start:row_end, col_start:col_end);
    
    % 找到区域内的主峰值
    [max_val, max_idx] = max(abs(y_region(:)));
    [n0_rel, m0_rel] = ind2sub(size(y_region), max_idx);
    n0 = row_start + n0_rel - 1;  % 全局多普勒索引
    m0 = col_start + m0_rel - 1;  % 全局索引
    n_p_est = n0;  % 主峰值位置输出
    m_p_est = m0;
    % 设置检测阈值
    threshold = threshold_ratio* abs(max_val);
    
    % 初始化路径参数
    path_count = 0;
    sigma_est = NaN;
   delay_taps = [];
  Doppler_taps = [];
   chan_coef  = [];
    detected_positions = false(size(y));  % 跟踪所有检测到的路径位置
    % 搜索有效路径
    for i = row_start:row_end
        for j = col_start:col_end
            if abs(y(i,j)) > threshold
                path_count = path_count + 1;
               
                % 记录绝对索引
               delay_taps(path_count) = j - m_p;  % 延迟索引(0-based)
                Doppler_taps(path_count) = i - n_p;  % 多普勒索引(0-based, 0到N-1)
                % 计算信道系数
                chan_coef(path_count) = y(i,j) / x_p;
                detected_positions(i,j) = true;
            end
        end
    end
    taps = path_count;
    
   % === 改进的噪声方差估计 ===
    % 1. 基于实际导频位置重新定义保护区域
    guard_col_start = max(1, m_p_est-m_max);
    guard_col_end   = min(M, m_p_est + m_max);
    % guard_row_start = 1;
    % guard_row_end   = N;
    guard_row_start = max(1,n_p_est-n_max);
    guard_row_end   = min(N,n_p_est+n_max);
    % guard_col_start = 1;
    % guard_col_end   = M;
    % 2. 创建保护区域掩码
    guard_region = false(size(y));
    guard_region(guard_row_start:guard_row_end, guard_col_start:guard_col_end) = true;
    
    % 3. 排除所有检测到的路径位置（包括导频和多径）
    guard_region(detected_positions) = false;
    
    % 4. 提取纯噪声样本
    noise_samples = y(guard_region);
    
    % 5. 计算噪声方差（使用中值估计提高鲁棒性）
    if ~isempty(noise_samples)
        % 使用中值绝对偏差(MAD)估计更鲁棒
        abs_noise = abs(noise_samples);
        median_abs = median(abs_noise);
        mad = median(abs(abs_noise - median_abs));
        sigma_est = (1.4826 * mad)^2;  % 高斯分布修正因子
    end
end
