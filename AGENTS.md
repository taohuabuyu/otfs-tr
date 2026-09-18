# OTFS-TR Engineering Instructions

## Scope

- These instructions apply to every file under this `OTFS-TR` project.
- Keep all project code, tests, results, and documentation inside this directory.
- Do not modify the source project `OTFS-WIDE-RX-STANDALONE` while working here.
- Preserve existing files and user changes; inspect before editing and avoid unrelated rewrites.

## Project objective

Build a compact MATLAB OTFS transceiver for two independent Ettus X310 devices with:

- 8-QAM at 10 MS/s TX and 20 MS/s RX;
- nominal design bandwidth of 10 MHz;
- design spectral efficiency greater than 2 bit/s/Hz;
- equivalent carrier-frequency/Doppler-offset tolerance greater than 500 kHz;
- measured BER below `1e-5` on a controlled, static, high-SNR link.

The configured center-frequency offset is an equivalent Doppler/CFO test. Do not describe it as a demonstrated physical vehicle-speed Doppler result.

## Design rules

- Reuse the proven OTFS modulation, demodulation, preamble synchronization, CFO correction, DD-pilot channel estimation, and MP-detection concepts from the source project.
- Keep one central user-editable configuration function. Do not duplicate scenario parameters across entry points.
- Keep TX, RX, and offline BER comparison as three separate executable stages. The TX stage must not construct an RX object, and the RX stage must not construct a TX object.
- Keep the executable flow visible: configure, build/save reference, transmit; capture/save raw IQ; then load both files, synchronize, correct CFO, demodulate, equalize/detect, calculate BER, and save evidence.
- Prefer small MATLAB functions and plain structs. Do not introduce classes, apps, frameworks, or unnecessary abstraction.
- TX and RX must use different X310 IP addresses and independent System objects.
- Treat TX underrun, RX overrun, incomplete captures, missing frames, insufficient tested bits, and non-finite BER as failed acceptance conditions.
- Never connect an X310 transmitter directly to a receiver. Require a verified RF attenuator or a suitable over-the-air setup.

## Metric definitions

- Design bit rate: `fsTx * log2(MMod)`.
- Design spectral efficiency: `designBitRateBps / signalBandwidthHz`.
- The design spectral-efficiency metric excludes preamble, CP, pilot, guard, and burst-silence overhead, matching the stated acceptance interpretation.
- BER uses only actual data positions outside the pilot and guard region.
- For zero observed errors, report the 95% upper bound `3 / testedBits`; do not claim `BER < 1e-5` unless the configured minimum bit count and acceptance rule are both satisfied.
- Report nominal bandwidth separately from measured occupied bandwidth.

## Validation and evidence

- Use class-based `matlab.unittest` tests for non-hardware behavior.
- Tests must cover configuration validation, waveform/reference consistency, design metrics, ±500/±600 kHz offline CFO recovery, and acceptance logic.
- Hardware tests are manual and must save configuration, diagnostics, estimated CFO, residual CFO, valid frames, tested bits, bit errors, BER, and acceptance decisions.
- Static checks, offline simulations, and old captures do not prove current two-X310 hardware performance.
- Do not state that BER, CFO tolerance, or occupied-bandwidth targets are achieved until a fresh hardware run supplies the corresponding evidence.

## Change completion

- Run applicable non-hardware tests and MATLAB code checks.
- Summarize changed files, validation results, hardware tests not run, and known limitations.
- Do not commit, push, delete material data, or create a pull request without explicit user confirmation.
