# OTFS-TR

面向两台独立 Ettus X310 的 MATLAB OTFS 收发验证工程。TX、RX和离线处理保持为独立阶段；当前软件联调采用双方预先持有的同一 MAT 测试用例，不要求两端交换运行标识或TX配置。

## 当前工作方式

- TX读取本机配置TXT，获得测试用例路径、等效频偏、发射时长和可选验收目标。
- RX读取自己的配置TXT；其中只包含RX本机的测试用例路径。
- MAT文件中的`case_id`被映射为32 bit空口编码，随受保护帧头发送。
- RX使用本地MAT重建参考比特，并检查空口用例编码是否与本地`case_id`一致。
- TX和RX分别生成本机`local_run_id`，仅用于防止结果目录重名，不在两端之间传递。
- RX中心频率固定为2.675 GHz，接收算法从捕获IQ中盲估计CFO。
- TX默认在完整数字基带波形上传X310前注入20 dB复AWGN；RX不接收该参数。

## 关键指标

- 默认调制：8-QAM。
- TX采样率：10 MS/s。
- RX采样率：20 MS/s。
- 名义带宽：10 MHz。
- 设计频谱效率：3 bit/s/Hz。
- 默认等效频偏：`-600 kHz`，搜索范围为`-800～800 kHz`。
- BER门限：`1e-5`。
- 最少测试比特：1,000,000 bit，零误码时同时要求`3/Nbits < 1e-5`。

配置中心为`otfs_tr_config.m`。中心频差只是等效CFO测试，不能描述为真实运动速度产生的物理多普勒。

TX加噪由以下中央配置控制：

```matlab
cfg.enableTxAwgn = true;   % false表示发送原始干净波形
cfg.txAwgnSnrDb = 20;      % TX数字基带注入SNR
cfg.txAwgnSeed = 20260929; % 固定种子，保证可复现
```

噪声覆盖前导、CP和OTFS数据在内的完整发射波形。加噪后保持原平均总功率，并进行峰值保护；`txRun.txAwgn`记录实际注入SNR、噪声功率、缩放系数和最终峰值。该SNR不是RX物理信道SNR。

## 测试用例格式

MAT文件必须包含标量结构体`test_case`：

```matlab
test_case.version = 1;
test_case.case_id = "CASE-OTFS-8QAM-001";
test_case.payload_bits = uint8(...); % 1881 x 1024，元素只能为0或1
```

工程内示例：

```text
test_cases/CASE-OTFS-8QAM-001-airid.mat
```

## 软件配置

TX配置TXT：

```text
testPayload=D:/cases/CASE-OTFS-8QAM-001-airid.mat
scenario=宽频带频偏
freq_offset_hz=-600000
targetBer=1e-5
targetSpectralEfficiency=2
duration_seconds=60
```

必填字段是`testPayload`和`freq_offset_hz`。其余字段可选。相对MAT路径以TXT所在目录为基准。

RX配置TXT只允许一个字段：

```text
testPayload=D:/rx_cases/CASE-OTFS-8QAM-001-airid.mat
```

## 两端启动

TX端：

```matlab
cd("D:\Program Files\MATLAB\R2025a\otfs");
addpath(pwd,'-begin');
rehash toolboxcache;
rehash;
txRun = run_otfs_tr_transmitter("D:/config/otfs_tx_cfg.txt");
```

看到板载连续发射已经启动的提示后，RX端执行：

```matlab
cd("D:\Program Files\MATLAB\R2025a\otfs");
addpath(pwd,'-begin');
rehash toolboxcache;
rehash;
rxRun = run_otfs_tr_receiver("D:/config/otfs_rx_cfg.txt");
```

RX完成采集后自动进行同步、CFO/SFO校正、OTFS解调、MP检测、BER计算并生成报告。`rxRun.responseFile`指向软件可读取的`response.json`。
帧检测期间会原子更新运行目录中的`progress.json`。默认每累计`100000`个有效、去重后的测试比特发布一次阶段BER；处理开始和完成状态也会写入该文件。可通过中心配置`cfg.progressUpdateEveryBits`改为`200000`等其他正整数阈值。
常规处理默认在指标和文本/JSON报告完成后立即返回，不生成耗时的PNG、FIG和结果MAT。需要完整诊断产物时，在中心配置中设置`cfg.generateDiagnosticArtifacts = true`后重新处理保存的IQ。
每次处理完成后，软件还按`参与BER统计的接收bit数 / RX接收时长`计算传输速率，并在控制台、`acceptance_report.txt`和`response.json`中显示。

不使用配置TXT时，RX只需提供本地测试用例；频偏始终从捕获IQ中估计：

```matlab
caseFile = fullfile(pwd,"test_cases","CASE-OTFS-8QAM-001-airid.mat");
rxRun = run_otfs_tr_receiver(caseFile);
```

## 结果目录

每次运行都在本机建立独立目录：

```text
results/pairs/<local_run_id>/
├─ pair_manifest.mat
├─ tx/reference_package.mat
├─ rx/rx_capture.mat
└─ reports/<timestamp>/
   ├─ response.json
   ├─ acceptance_report.txt
   ├─ otfs_tr_result.mat
   └─ diagnostic_plots/
```

RX使用本地测试用例重建参考时，结果会标明`reference_origin=rx-local-test-case`和`transmitter_status_verified=false`。这可以计算BER并确认空口用例编码，但不能证明远端TX运行状态。完整硬件验收需显式使用同一次发射保存的`reference_package.mat`和对应`rx_capture.mat`：

```matlab
result = run_otfs_tr_offline_decode(referenceFile, captureFile);
```

## 验证

非硬件回归：

```matlab
run_all_tests
```

硬件验收必须保存配置、原始IQ、估计CFO、残余CFO、有效帧数、测试比特数、误码数、BER和验收结论。禁止将静态检查、离线仿真或历史捕获描述为本次双X310硬件通过。

禁止直接用无衰减射频线连接两台X310，必须使用经确认的衰减链路或合适的空口环境。

详细模块说明见`代码说明.md`。
