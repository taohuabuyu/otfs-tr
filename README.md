# OTFS-TR

面向两台 Ettus X310 的简化 OTFS 收发验证工程。工程复用
`OTFS-WIDE-RX-STANDALONE` 的 OTFS 网格、单导频、前导同步和分级 CFO
校正、DD域信道估计和MP检测代码。新工程仅集中配置，并将原来同一入口中的
USRP发射与接收拆到两台X310和两个MATLAB会话中。

## 设计目标

- 8-QAM，10 MS/s 发射复基带采样率；
- 名义信号带宽 10 MHz；
- 不计同步、CP、导频和保护区开销的设计频谱效率为 3 bit/s/Hz；
- 使用两台独立 X310，默认验证 ±600 kHz 等效多普勒/载波频偏；
- 实测 BER 小于 `1e-5` 才判定通过。

默认TX预生成约0.1秒的连续帧缓冲区，并通过`basebandTransmitter`上传到X310的
板载内存连续循环播放。每帧包含63样点前导、64样点CP和单导频保护区，不在循环
缓冲区之间插入静默。RX一次采集0.05秒原始IQ，
采集期间不执行同步、绘图或磁盘写入。离线处理从整个窗口寻找所有前导。解调
帧数根据调制阶数、BER目标和接收窗口自动计算；默认8-QAM最多解调163帧，至少
需要148个有效帧（300,588 bit）才能满足零误码时的95%上界要求。
TX持续发射阶段不再由主机实时推送IQ，因此避免USB网卡TX sequence error破坏连续
波形。RX通过`basebandReceiver`先把固定窗口采入X310板载内存，采集完成后再下载
到主机，避免20 MS/s实时网口拉流造成丢包或overrun；MATLAB内部处理为浮点，
TX/RX射频采样率为10/20 MS/s。

这里的 600 kHz 是通过 TX/RX 中心频率差构造的等效频偏，并不等同于真实运动速度造成的物理多普勒。

## 文件

| 文件 | 用途 |
|---|---|
| `otfs_tr_config.m` | 唯一的用户配置入口 |
| `run_otfs_tr_transmitter.m` | TX会话：生成参考数据并控制发射X310 |
| `run_otfs_tr_receiver.m` | RX会话：建立任务包、控制接收X310并保存原始IQ |
| `run_otfs_tr_offline_decode.m` | 离线读取TX参考与RX采集，计算BER并判定 |
| `otfs_tr_prepare_pair.m` | 建立本轮RX任务包及TX参考文件投放目录 |
| `otfs_tr_find_latest_pair.m` | 查找最新且同时包含TX/RX文件的完整任务包 |
| `otfs_tr_correct_sfo.m` | 从连续前导估计采样频偏并校正整段20 MHz IQ |
| `run_otfs_tr_link.m` | 离线对比的兼容别名，不操作射频硬件 |
| `run_otfs_tr_offline_test.m` | 无硬件的 ±600 kHz 基带链路测试 |
| `run_all_tests.m` | 工程测试入口 |
| `otfs_tr_build_waveform.m` | 构建连续可配置QAM OTFS TX缓冲区与参考比特 |
| `wide_rx_process_capture.m` | 分级CFO校正、全窗口前导搜索和OTFS接收主链路 |
| `channel_estimation_for_ZF.m` / `OTFS_MP_Detection.m` | 原工程DD信道估计和MP检测 |
| `otfs_tr_save_report.m` | 保存 MAT/文本验收结果 |
| `OTFS_modulation.m` / `OTFS_demodulation.m` | OTFS 变换 |
| `addpilot.m` | DD 域单导频和保护区映射 |

## 首次使用

1. 在 `otfs_tr_config.m` 中确认两台设备的IP地址，并分别在两台电脑确认
   `cfg.txRadioConfiguration`、`cfg.rxRadioConfiguration`与`radioConfigurations`
   显示的配置名称一致。
2. 默认TX X310为`192.168.10.2`并使用B板`RFB:TX/RX`；RX X310为
   `192.168.10.3`并使用A板`RFA:RX2`。
3. 两台X310必须通过经过验证的足够衰减射频链路或空口连接，禁止直接射频线连接。
4. 先运行：

```matlab
run_all_tests
```

5. 打开两个MATLAB会话。在TX会话先启动30秒发射：

```matlab
txRun = run_otfs_tr_transmitter(30);
```

6. 在发射仍在运行时，在RX会话采集原始IQ。例如验证+600 kHz中心频差：

```matlab
rxRun = run_otfs_tr_receiver(+600e3);
```

RX会为本轮采集建立如下任务包：

```text
results/pairs/<接收时间>/rx/rx_capture.mat
results/pairs/<接收时间>/tx/
```

7. 等TX会话结束后，把TX端最终的`reference_package.mat`复制到命令行打印的
`rxRun.referenceDropDirectory`中。正式验收必须复制发射结束后的最终文件，因为其中
包含完整的TX运行状态。复制过程中可以先使用`.partial`后缀，完成后再改回
`reference_package.mat`，避免离线程序读取未复制完整的文件。

8. 在RX会话中直接执行无参数离线对比。程序只会选择最新且同时包含TX参考和RX
采集文件的完整任务包：

```matlab
result = run_otfs_tr_offline_decode();
```

也可以指定任务包目录：

```matlab
result = run_otfs_tr_offline_decode(rxRun.pairDirectory);
```

原有的双文件调用仍然保留：

```matlab
result = run_otfs_tr_offline_decode( ...
    txRun.referenceFile, rxRun.captureFile);
```

验证负频差时重新执行上述流程，并将RX命令改为：

```matlab
rxRun = run_otfs_tr_receiver(-600e3);
```

TX脚本只构造发射对象，RX脚本只构造接收对象。BER不会在采集阶段计算，只有离线
对比阶段才读取TX参考比特和RX原始IQ。只有离线结果中的
`result.acceptance.pass=true`才表示本组数据满足全部验收条件。

默认TX把约0.1秒的预生成缓冲区一次上传到X310板载内存，然后由硬件连续回放；
持续发射期间不需要主机实时供数。RX使用一次固定长度调用接收1,000,000个20 MHz
样点到X310板载内存，采集结束后再下载并保存。这种设计从架构上消除TX主机欠载，
并避免RX采集窗口内的网卡吞吐和MATLAB/磁盘调度造成overrun。

## 验收口径

设计频谱效率：

```text
R_design = fsTx * log2(MMod) = 10 MS/s * 3 = 30 Mbit/s
eta_design = R_design / B_nominal = 30 Mbit/s / 10 MHz = 3 bit/s/Hz
```

BER 使用导频保护区以外的真实数据比特统计。零误码时同时要求95%上限
`3/Nbits < 1e-5`；默认最低比较位数为300,001 bit，对应至少148个完整8-QAM
有效帧。`minimumValidFrames`与`maxDecodedFrames`均由配置自动推导。

## 已知边界

- 默认验收环境为受控、高SNR、静态链路；复杂时变无线多径不是本工程的首要验收环境。
- 10 MHz 是名义设计带宽；99% 实际占用带宽需要单独通过频谱分析验证。
- 当前8-QAM设计频谱效率为3 bit/s/Hz，满足大于2 bit/s/Hz的设计指标；实机BER
  是否达标仍必须由本轮硬件采集单独证明。
- 实机结果仍取决于衰减、增益、端口、时钟、削顶、欠载和过载状态。
- 当前接收算法与原工程一致，使用单导频DD信道估计和MP检测，没有替换为简化单抽头算法。
- `run_all_tests`和`run_otfs_tr_offline_test`属于非硬件验证，不能替代两台X310实测报告。
- 软件仿真、静态检查和无overrun/underrun的代码路径不能代替真实双X310采集证据。
- 两台独立X310若不共享10 MHz参考，仍可能存在采样时钟偏差；必要时需要外部参考或SFO跟踪。
- 默认开启软件SFO补偿。它根据整段采集中多个前导的分数位置拟合实际帧间隔，
  再把20 MHz IQ重采样到名义帧间隔。可设置`cfg.enableSfoCompensation=false`
  恢复原始处理路径；软件补偿不能替代对高质量共同10 MHz参考的硬件验证。
