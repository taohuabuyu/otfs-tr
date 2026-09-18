classdef otfsTrTest < matlab.unittest.TestCase
    %otfsTrTest Non-hardware verification for the OTFS-TR public API.

    properties (TestParameter)
        offsetCase = struct( ...
            "positive500k", 500e3, ...
            "negative500k", -500e3, ...
            "positive600k", 600e3, ...
            "negative600k", -600e3)
        modulationCase = struct( ...
            "qpsk", struct("order", 4, "bitsPerFrame", 1354, ...
                "minimumFrames", 222, "decodedFrames", 245), ...
            "qam8", struct("order", 8, "bitsPerFrame", 2031, ...
                "minimumFrames", 148, "decodedFrames", 163), ...
            "qam16", struct("order", 16, "bitsPerFrame", 2708, ...
                "minimumFrames", 111, "decodedFrames", 123))
    end

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testDesignSpectralEfficiency(testCase)
            cfg = otfs_tr_config();

            actual = cfg.designSpectralEfficiency;

            testCase.verifyEqual(actual, log2(cfg.MMod), AbsTol=1e-12);
            testCase.verifyGreaterThanOrEqual(actual, ...
                cfg.minimumSpectralEfficiency);
            testCase.verifyEqual(cfg.designBitRateBps, ...
                cfg.fsTx*log2(cfg.MMod), AbsTol=1e-6);
            testCase.verifyEqual(cfg.txTransportDataType, "int16");
            testCase.verifyEqual(cfg.rxTransportDataType, "int16");
            testCase.verifyEqual(cfg.txTransportPayloadRateBps, 320e6);
            testCase.verifyEqual(cfg.rxTransportPayloadRateBps, 640e6);
        end

        function testWaveformAndReferenceLengths(testCase)
            cfg = otfsTrTest.fastConfiguration();

            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);

            expectedBitsPerFrame = (cfg.N*cfg.M - ...
                (2*cfg.nMax+1)*(2*cfg.mMax+1))*cfg.MBits;
            expectedFrameLength = cfg.preambleLen + cfg.cpLen + cfg.N*cfg.M;
            expectedBurstLength = cfg.txBufferFrameCount*expectedFrameLength;
            testCase.verifyEqual(reference.effectiveBitsPerFrame, ...
                expectedBitsPerFrame);
            testCase.verifyEqual(numel(txSignal), expectedBurstLength);
            testCase.verifyEqual(numel(training.preamble10), cfg.preambleLen);
            testCase.verifyEqual(params.MMod, cfg.MMod);
            testCase.verifyLessThanOrEqual(reference.actualTxPeak, ...
                cfg.hardwareTxPeak + 1e-12);
        end

        function testAutomaticFrameLimits(testCase, modulationCase)
            cfg = otfs_tr_config(modulationCase.order);

            testCase.verifyEqual(cfg.effectiveBitsPerFrame, ...
                modulationCase.bitsPerFrame);
            testCase.verifyEqual(cfg.minimumValidFrames, ...
                modulationCase.minimumFrames);
            testCase.verifyEqual(cfg.maxDecodedFrames, ...
                modulationCase.decodedFrames);
            testCase.verifyGreaterThanOrEqual(cfg.maxDecodedFrames, ...
                cfg.minimumValidFrames);
            testCase.verifyLessThanOrEqual(cfg.maxDecodedFrames, ...
                cfg.availableCaptureFrames);
        end

        function testPositiveAndNegativeCfoRecovery(testCase, offsetCase)
            cfg = otfsTrTest.fastConfiguration();

            result = otfs_tr_simulate_link(cfg, offsetCase, Inf);

            testCase.verifyEqual(result.cfoEstimateHz, offsetCase, AbsTol=100);
            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.ber, 0, AbsTol=0);
        end

        function testRejectsNonIntegerSampleRateRatio(testCase)
            cfg = otfs_tr_config();
            cfg.fsRx = 15e6;

            operation = @() otfs_tr_validate_config(cfg);

            testCase.verifyError(operation, ...
                "otfs_tr:InvalidSampleRateRatio");
        end

        function testRejectsSameRadioAddress(testCase)
            cfg = otfs_tr_config();
            cfg.rxAddress = cfg.txAddress;

            operation = @() otfs_tr_validate_config(cfg);

            testCase.verifyError(operation, "otfs_tr:SameRadioAddress");
        end

        function testRejectsInvalidTransportDataType(testCase)
            cfg = otfs_tr_config();
            cfg.txTransportDataType = "float32";

            operation = @() otfs_tr_validate_config(cfg);

            testCase.verifyError(operation, ...
                "otfs_tr:InvalidTransportDataType");
        end

        function testAcceptancePassesQualifiedResult(testCase)
            cfg = otfs_tr_config();
            qualifiedBits = cfg.minimumValidFrames*cfg.effectiveBitsPerFrame;
            result = struct("ber", 0, "totalBits", qualifiedBits, ...
                "totalErrors", 0, "requestedDopplerHz", 600e3, ...
                "validFrames", cfg.minimumValidFrames, ...
                "cfoEstimateHz", 600e3, "residualCfoHz", 0);
            radioStatus = struct("txRepeatStarted", true, ...
                "txCompleted", true, "anyTxUnderrun", false, ...
                "anyRxOverrun", false, "captureComplete", true, ...
                "totalReceivedSamples", 1000);

            acceptance = otfs_tr_evaluate_acceptance( ...
                cfg, result, radioStatus);

            testCase.verifyTrue(acceptance.pass);
            testCase.verifyLessThan(acceptance.zeroErrorBerUpper95, ...
                cfg.maximumBer);
        end

        function testAcceptanceRejectsInsufficientBits(testCase)
            cfg = otfs_tr_config();
            result = struct("ber", 0, "totalBits", 10000, ...
                "totalErrors", 0, "requestedDopplerHz", 600e3, ...
                "validFrames", 5, "cfoEstimateHz", 600e3, ...
                "residualCfoHz", 0);

            acceptance = otfs_tr_evaluate_acceptance( ...
                cfg, result, struct());

            testCase.verifyFalse(acceptance.testBitsPass);
            testCase.verifyFalse(acceptance.pass);
        end

        function testAcceptanceRejectsUnprovenZeroErrorBer(testCase)
            cfg = otfs_tr_config();
            result = struct("ber", 0, "totalBits", 60930, ...
                "totalErrors", 0, "requestedDopplerHz", 600e3, ...
                "validFrames", 30, "cfoEstimateHz", 600e3, ...
                "residualCfoHz", 0);

            acceptance = otfs_tr_evaluate_acceptance( ...
                cfg, result, struct());

            testCase.verifyFalse(acceptance.zeroErrorConfidencePass);
            testCase.verifyFalse(acceptance.pass);
        end

        function testAcceptanceRejectsIncompleteCapture(testCase)
            cfg = otfs_tr_config();
            qualifiedBits = cfg.minimumValidFrames*cfg.effectiveBitsPerFrame;
            result = struct("ber", 0, "totalBits", qualifiedBits, ...
                "totalErrors", 0, "requestedDopplerHz", 600e3, ...
                "validFrames", cfg.minimumValidFrames, ...
                "cfoEstimateHz", 600e3, "residualCfoHz", 0);
            radioStatus = struct("txRepeatStarted", true, ...
                "txCompleted", true, "anyTxUnderrun", false, ...
                "anyRxOverrun", false, "captureComplete", false, ...
                "totalReceivedSamples", 1000);

            acceptance = otfs_tr_evaluate_acceptance( ...
                cfg, result, radioStatus);

            testCase.verifyFalse(acceptance.radioPass);
            testCase.verifyFalse(acceptance.pass);
        end

        function testAcceptancePassesSuccessfulOnboardReplay(testCase)
            cfg = otfs_tr_config();
            qualifiedBits = cfg.minimumValidFrames*cfg.effectiveBitsPerFrame;
            result = struct("ber", 0, "totalBits", qualifiedBits, ...
                "totalErrors", 0, "requestedDopplerHz", 600e3, ...
                "validFrames", cfg.minimumValidFrames, ...
                "cfoEstimateHz", 600e3, "residualCfoHz", 0);
            radioStatus = struct("txRepeatStarted", true, ...
                "txCompleted", true, ...
                "txExecutionMode", "onboard-continuous", ...
                "txOnboardReplayStarted", true, ...
                "txOnboardReplayStopped", true, ...
                "txNoApiError", true, ...
                "anyRxOverrun", false, "captureComplete", true, ...
                "totalReceivedSamples", 1000);

            acceptance = otfs_tr_evaluate_acceptance( ...
                cfg, result, radioStatus);

            testCase.verifyTrue(acceptance.txTransportPass);
            testCase.verifyTrue(acceptance.pass);
        end

        function testHardwareEntriesAreSeparated(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));

            txText = fileread(fullfile(projectRoot, ...
                "run_otfs_tr_transmitter.m"));
            rxText = fileread(fullfile(projectRoot, ...
                "run_otfs_tr_receiver.m"));

            testCase.verifyFalse(contains(txText, "SDRuReceiver"));
            testCase.verifyTrue(contains(txText, "basebandTransmitter"));
            testCase.verifyFalse(contains(rxText, "SDRuTransmitter"));
            testCase.verifyTrue(contains(rxText, "basebandReceiver"));
            testCase.verifyFalse(contains(rxText, ...
                "otfs_tr_process_capture"));
        end

        function testSavedReferenceAndCaptureOfflineDecode(testCase)
            cfg = otfsTrTest.fastConfiguration();
            tempRoot = string(tempname);
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));

            [referenceFile, captureFile] = ...
                otfsTrTest.createSavedPair(cfg, tempRoot, 600e3);
            result = run_otfs_tr_offline_decode(referenceFile, captureFile);

            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.cfoEstimateHz, 600e3, AbsTol=100);
        end

        function testSavedPairDirectoryOfflineDecode(testCase)
            cfg = otfsTrTest.fastConfiguration();
            tempRoot = string(tempname);
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));
            cfg.resultRoot = tempRoot;
            pair = otfs_tr_prepare_pair(cfg);
            sourceDirectory = fullfile(tempRoot, "source");
            mkdir(sourceDirectory);
            [referenceFile, captureFile] = ...
                otfsTrTest.createSavedPair(cfg, sourceDirectory, 600e3);
            copyfile(referenceFile, pair.expectedReferenceFile);
            copyfile(captureFile, pair.captureFile);

            result = run_otfs_tr_offline_decode(pair.pairDirectory);

            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.pairDirectory, pair.pairDirectory);
            testCase.verifyTrue(startsWith(result.report.directory, ...
                pair.reportDirectory));
        end

        function testArbitraryWindowFindsRepeatedFrames(testCase)
            cfg = otfsTrTest.fastConfiguration();
            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);
            rx20 = resample(repmat(txSignal, 2, 1), 2, 1);
            rx20 = rx20(778:end-321);
            n = (0:numel(rx20)-1).';
            rx20 = rx20 .* exp(1j*2*pi*600125/cfg.fsRx*n);

            processed = wide_rx_process_capture(rx20, training, params, ...
                reference.bitsPerFrame, cfg);
            result = otfs_tr_finalize_result(processed, 600125, cfg);

            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyLessThanOrEqual( ...
                abs(result.cfoEstimateHz-600125), 250);
            testCase.verifyGreaterThan(result.detectedPreambles, ...
                cfg.maxDecodedFrames);
        end
    end

    methods (Static, Access=private)
        function cfg = fastConfiguration()
            cfg = otfs_tr_config();
            cfg.txBufferFrameCount = 8;
            cfg.txBurstLength = cfg.txBufferFrameCount*cfg.frameLength10;
            cfg.maxDecodedFrames = 6;
            cfg.captureCallCount = 1;
            cfg.captureBurstCount = 1;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 500;
            cfg.frameResidualCfoSearchHz = -1000:100:1000;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
        end


        function [referenceFile, captureFile] = ...
                createSavedPair(cfg, tempRoot, cfoHz)
            cfg.resultRoot = tempRoot;
            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);
            ratio = cfg.fsRx/cfg.fsTx;
            rx20 = resample(repmat(txSignal, cfg.captureBurstCount, 1), ...
                ratio, 1);
            n = (0:numel(rx20)-1).';
            rx20 = rx20 .* exp(1j*2*pi*cfoHz/cfg.fsRx*n);
            txStatus = struct("started", true, "completed", true, ...
                "anyTxUnderrun", false);
            radioStatus = struct("captureCalls", cfg.captureBurstCount, ...
                "anyRxOverrun", false, ...
                "captureComplete", true, ...
                "totalReceivedSamples", numel(rx20));
            equivalentDopplerHz = cfoHz;
            referenceFile = fullfile(tempRoot, "reference_package.mat");
            captureFile = fullfile(tempRoot, "rx_capture.mat");
            save(referenceFile, "cfg", "params", "training", ...
                "reference", "txStatus");
            save(captureFile, "cfg", "rx20", "radioStatus", ...
                "equivalentDopplerHz");
        end
    end
end
