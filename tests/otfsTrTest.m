classdef otfsTrTest < matlab.unittest.TestCase
    %otfsTrTest Non-hardware verification for the OTFS-TR public API.

    properties (TestParameter)
        offsetCase = struct( ...
            "positive500k", 500e3, ...
            "negative500k", -500e3, ...
            "positive600k", 600e3, ...
            "negative600k", -600e3)
        modulationCase = struct( ...
            "qpsk", struct("order", 4, "bitsPerFrame", 1300, ...
                "minimumFrames", 770, "decodedFrames", 848), ...
            "qam8", struct("order", 8, "bitsPerFrame", 1608, ...
                "minimumFrames", 622, "decodedFrames", 685), ...
            "qam16", struct("order", 16, "bitsPerFrame", 2652, ...
                "minimumFrames", 378, "decodedFrames", 416))
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

        function testFixedRxCenterAndRequestedTxOffset(testCase, offsetCase)
            cfg = otfs_tr_config();
            fixedRxCenter = cfg.rxCenterFrequencyHz;

            configured = otfs_tr_apply_equivalent_cfo(cfg, offsetCase);

            testCase.verifyEqual(configured.rxCenterFrequencyHz, ...
                fixedRxCenter, AbsTol=1e-6);
            testCase.verifyEqual(configured.txCenterFrequencyHz, ...
                fixedRxCenter-offsetCase, AbsTol=1e-6);
            testCase.verifyEqual(configured.txCenterFrequencyHz- ...
                configured.rxCenterFrequencyHz, -offsetCase, ...
                AbsTol=1e-6);
            testCase.verifyWarningFree( ...
                @() otfs_tr_validate_config(configured));
        end

        function testRejectsInconsistentRfCenters(testCase)
            cfg = otfs_tr_config();
            cfg.txCenterFrequencyHz = cfg.txCenterFrequencyHz + 1e3;

            testCase.verifyError(@() otfs_tr_validate_config(cfg), ...
                "otfs_tr:InconsistentCenterFrequency");
        end

        function testWaveformAndReferenceLengths(testCase)
            cfg = otfsTrTest.fastConfiguration();

            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);

            expectedBitsPerFrame = cfg.effectiveBitsPerFrame;
            expectedFrameLength = cfg.preambleLen + cfg.cpLen + cfg.N*cfg.M;
            expectedBurstLength = cfg.txBufferFrameCount*expectedFrameLength;
            testCase.verifyEqual(reference.effectiveBitsPerFrame, ...
                expectedBitsPerFrame);
            testCase.verifyEqual(numel(txSignal), expectedBurstLength);
            testCase.verifyEqual(numel(training.preamble10), cfg.preambleLen);
            testCase.verifyEqual(params.MMod, cfg.MMod);
            testCase.verifyEqual(size(reference.payloadBitsByFrame), ...
                [cfg.payloadBitsPerFrame cfg.superframeLength]);
            testCase.verifyEqual(size(reference.berTestBitsByFrame), ...
                [cfg.berTestBitsPerFrame cfg.superframeLength]);
            testCase.verifyEqual(reference.referenceMode, ...
                "unique-superframe");
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
            testCase.verifyTrue(result.referenceAlignmentPass);
            testCase.verifyTrue(isfinite(result.softEvmPercentMedian));
            testCase.verifyLessThan(result.softEvmPercentMedian, 1e-3);
            testCase.verifyGreaterThan(result.decisionConfidenceMedian, ...
                0.99);
            testCase.verifyEqual(result.bitErrorsByPlane, ...
                zeros(1, cfg.MBits));
            testCase.verifyEqual(result.ddPilotCfoFallbackFrames, 0);
            testCase.verifyEqual(result.rowBiasCorrectedFrames, 0);
            testCase.verifyEqual(result.mpNoiseCalibrationFrames, 0);
            testCase.verifyTrue(isfinite(result.sigmaEffectiveMedian));
        end

        function testFractionalTimingRecoveryUsesKnownTraining(testCase)
            cfg = otfsTrTest.fastConfiguration();
            cfg.enableFractionalTimingCompensation = true;
            cfg.fractionalTimingSearchSamples10 = -0.30:0.02:0.30;
            cfg.fractionalTimingEstimationFrames = 4;
            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);
            rx20 = resample(txSignal, cfg.fsRx/cfg.fsTx, 1);
            sampleIndex = (1:numel(rx20)).';
            rx20 = interp1(sampleIndex, rx20, sampleIndex+0.36, ...
                "pchip", 0);

            processed = wide_rx_process_capture(rx20, training, params, ...
                reference, cfg);
            result = otfs_tr_finalize_result(processed, 0, cfg);

            testCase.verifyTrue(result.fractionalTimingInfo.applied);
            testCase.verifyEqual( ...
                result.fractionalTimingInfo.selectedOffsetSamples10, ...
                -0.18, AbsTol=0.06);
            testCase.verifyGreaterThan( ...
                result.fractionalTimingInfo.improvementRatio, 1.01);
            testCase.verifyLessThan( ...
                result.fractionalTimingInfo.searchSampleReductionRatio, 1);
            testCase.verifyLessThan( ...
                result.fractionalTimingInfo.searchInterpolatedSamples, ...
                result.fractionalTimingInfo.fullCaptureEquivalentSamples);
            testCase.verifyEqual(result.totalErrors, 0);
        end

        function testStructuredRowBiasCorrectionReducesInjectedDc(testCase)
            cfg = otfsTrTest.fastConfiguration(8);
            [txSignal, reference, params, training] = ...
                otfs_tr_build_waveform(cfg);
            txSignal = otfsTrTest.addPayloadOffset( ...
                txSignal, cfg, 0.02+0.02i);
            rx20 = resample(txSignal, cfg.fsRx/cfg.fsTx, 1);
            disabledCfg = cfg;
            disabledCfg.enableStructuredRowBiasCorrection = false;
            disabledCfg.enableMpNoiseVarianceCalibration = false;

            baseline = otfs_tr_finalize_result( ...
                wide_rx_process_capture(rx20, training, params, ...
                reference, disabledCfg), 0, disabledCfg);
            corrected = otfs_tr_finalize_result( ...
                wide_rx_process_capture(rx20, training, params, ...
                reference, cfg), 0, cfg);

            testCase.verifyGreaterThan(baseline.totalErrors, 0);
            testCase.verifyLessThan(corrected.totalErrors, ...
                baseline.totalErrors);
            testCase.verifyGreaterThan(corrected.rowBiasCorrectedFrames, 0);
            testCase.verifyEqual(find( ...
                corrected.rowBiasApplicationCountByRow > 0), 1);
        end

        function testFrameHeaderRoundTrip(testCase, modulationCase)
            cfg = otfs_tr_config(modulationCase.order);
            frameId = cfg.superframeLength-1;

            mappedBits = otfs_tr_encode_frame_header(frameId, cfg);
            [actualId, valid] = otfs_tr_decode_frame_header(mappedBits, cfg);

            testCase.verifyTrue(valid);
            testCase.verifyEqual(actualId, frameId);
            testCase.verifyEqual(numel(mappedBits), cfg.headerMappedBits);
        end

        function testFrameHeaderCorrectsOneRepeatedBit(testCase)
            cfg = otfs_tr_config(8);
            mappedBits = otfs_tr_encode_frame_header(137, cfg);
            mappedBits(2) = ~mappedBits(2);

            [actualId, valid] = otfs_tr_decode_frame_header(mappedBits, cfg);

            testCase.verifyTrue(valid);
            testCase.verifyEqual(actualId, 137);
        end

        function testSuperframeHasEnoughUniqueBits(testCase, modulationCase)
            cfg = otfs_tr_config(modulationCase.order);

            testCase.verifyGreaterThanOrEqual( ...
                cfg.totalUniquePayloadBits, cfg.minimumTestBits);
            testCase.verifyGreaterThanOrEqual( ...
                cfg.maxDecodedFrames*cfg.effectiveBitsPerFrame, ...
                cfg.targetTestBits);
            testCase.verifyLessThanOrEqual( ...
                cfg.maxDecodedFrames, cfg.superframeLength);
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

        function testDiagnosticArtifactsAreDisabledByDefault(testCase)
            % Arrange and act.
            cfg = otfs_tr_config();

            % Assert.
            testCase.verifyFalse(cfg.generateDiagnosticArtifacts);
        end

        function testRejectsInvalidDiagnosticArtifactFlag(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.generateDiagnosticArtifacts = 2;

            % Act.
            operation = @() otfs_tr_validate_config(cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:InvalidDiagnosticArtifactConfiguration");
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

        function testUnknownRequestedCfoUsesBlindEstimate(testCase)
            cfg = otfs_tr_config();
            qualifiedBits = cfg.minimumValidFrames*cfg.effectiveBitsPerFrame;
            result = struct("ber", 0, "totalBits", qualifiedBits, ...
                "totalErrors", 0, "requestedDopplerHz", NaN, ...
                "validFrames", cfg.minimumValidFrames, ...
                "cfoEstimateHz", 600e3, "residualCfoHz", 0);

            acceptance = otfs_tr_evaluate_acceptance(cfg, result);

            testCase.verifyEqual(acceptance.dopplerSource, "estimated_cfo");
            testCase.verifyEqual(acceptance.testedDopplerHz, ...
                600e3, AbsTol=1e-6);
            testCase.verifyTrue(acceptance.dopplerPass);
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

        function testRxSavesCaptureBeforePreparingLocalReference(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            rxText = fileread(fullfile(projectRoot, ...
                "run_otfs_tr_receiver.m"));

            captureSavePosition = strfind(rxText, "save(captureFile");
            configLoadPosition = strfind(rxText, ...
                "otfs_tr_load_receiver_config(");
            referencePosition = strfind(rxText, ...
                "otfs_tr_prepare_local_reference(");

            testCase.verifyNumElements(captureSavePosition, 1);
            testCase.verifyNumElements(configLoadPosition, 1);
            testCase.verifyNumElements(referencePosition, 1);
            testCase.verifyLessThan(captureSavePosition, configLoadPosition);
            testCase.verifyLessThan(captureSavePosition, referencePosition);
        end

        function testSavedReferenceAndCaptureOfflineDecode(testCase)
            cfg = otfsTrTest.fastConfiguration();
            cfg.generateDiagnosticArtifacts = true;
            tempRoot = string(tempname);
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));

            [referenceFile, captureFile] = ...
                otfsTrTest.createSavedPair(cfg, tempRoot, 600e3);
            result = run_otfs_tr_offline_decode(referenceFile, captureFile);

            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.cfoEstimateHz, 600e3, AbsTol=100);
            expectedReceiveDuration = numel(result.rx20)/cfg.fsRx;
            expectedTransferRate = result.totalBits/expectedReceiveDuration;
            testCase.verifyEqual(result.receiveDurationSeconds, ...
                expectedReceiveDuration, AbsTol=1e-12);
            testCase.verifyEqual(result.receivedBitsForRate, result.totalBits);
            testCase.verifyEqual(result.transferRateBps, ...
                expectedTransferRate, AbsTol=1e-6);
            testCase.verifyTrue(all(isfile(result.diagnosticPlotFiles)));
            testCase.verifyTrue(isfile(result.report.responseFile));
            testCase.verifyTrue(isfile(result.report.metricsResponseFile));
            testCase.verifyTrue(isfile(result.report.artifactsResponseFile));
            metricsResponse = jsondecode(fileread( ...
                result.report.metricsResponseFile));
            artifactsResponse = jsondecode(fileread( ...
                result.report.artifactsResponseFile));
            testCase.verifyEqual(string(metricsResponse.stage), ...
                "metrics_completed");
            testCase.verifyEqual(string(metricsResponse.status), ...
                "processing");
            testCase.verifyEqual( ...
                metricsResponse.metrics.receive_duration_seconds, ...
                expectedReceiveDuration, AbsTol=1e-12);
            testCase.verifyEqual(metricsResponse.metrics.transfer_rate_bps, ...
                expectedTransferRate, AbsTol=1e-6);
            reportText = fileread(result.report.textFile);
            testCase.verifyTrue(contains(reportText, ...
                "received bits for transfer rate = "));
            testCase.verifyTrue(contains(reportText, "transfer rate = "));
            testCase.verifyFalse( ...
                logical(metricsResponse.artifacts.result_mat_ready));
            testCase.verifyEqual(string(artifactsResponse.stage), ...
                "artifacts_completed");
            testCase.verifyEqual(string(artifactsResponse.status), ...
                "completed");
            testCase.verifyTrue( ...
                logical(artifactsResponse.artifacts.result_mat_ready));
            testCase.verifyTrue(isfile(result.report.matFile));
            archived = load(result.report.matFile, "result");
            testCase.verifyEqual( ...
                string(archived.result.diagnosticsStorage.mode), ...
                "compact");
            testCase.verifyFalse(isfield(archived.result, "rx20"));
            testCase.verifyNotEmpty( ...
                archived.result.frameDiagnostics(1).rxGrid);
            testCase.verifyEmpty( ...
                archived.result.frameDiagnostics(6).rxGrid);
            testCase.verifyEqual(archived.result.totalErrors, 0);
            testCase.verifyEqual(result.application.decodedText, "TEST");
            testCase.verifyTrue(result.application.pass);
            testCase.verifyEqual( ...
                result.softwareResponse.artifacts.constellation_image_path, ...
                result.diagnosticPlotFiles(contains( ...
                result.diagnosticPlotFiles, "constellation_8qam.png")));
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
            latestResponseFile = fullfile(pair.pairDirectory, ...
                "response.json");
            latestResponse = jsondecode(fileread(latestResponseFile));
            manifest = load(pair.manifestFile, "pairManifest");
            testCase.verifyEqual(string(latestResponse.stage), ...
                "artifacts_skipped");
            testCase.verifyEqual(string(latestResponse.status), ...
                "completed");
            testCase.verifyEqual(string(latestResponse.artifacts.status), ...
                "skipped");
            testCase.verifyEqual(string( ...
                manifest.pairManifest.processingStage), ...
                "artifacts_skipped");
            testCase.verifyEqual(string(manifest.pairManifest.status), ...
                "processed");
            testCase.verifyFalse(result.artifactsGenerated);
            testCase.verifyEmpty(result.diagnosticPlotFiles);
            testCase.verifyFalse(isfile(result.report.matFile));
            testCase.verifyFalse(isfolder(fullfile( ...
                result.report.directory, "diagnostic_plots")));
            testCase.verifyTrue(isfile( ...
                result.report.artifactsResponseFile));
        end

        function testRejectsMismatchedWaveformVersions(testCase)
            cfg = otfsTrTest.fastConfiguration();
            tempRoot = string(tempname);
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));
            [referenceFile, captureFile] = ...
                otfsTrTest.createSavedPair(cfg, tempRoot, 600e3);
            capture = load(captureFile);
            capture.cfg.waveformVersion = 1;
            save(captureFile, "-struct", "capture");

            operation = @() run_otfs_tr_offline_decode( ...
                referenceFile, captureFile);

            testCase.verifyError(operation, ...
                "otfs_tr:IncompatibleTxRxConfiguration");
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
                reference, cfg);
            result = otfs_tr_finalize_result(processed, 600125, cfg);

            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyLessThanOrEqual( ...
                abs(result.cfoEstimateHz-600125), 250);
            testCase.verifyGreaterThan(result.detectedPreambles, ...
                cfg.maxDecodedFrames);
            testCase.verifyTrue(result.referenceAlignmentPass);
            validIds = result.frameIds(isfinite(result.frameIds));
            testCase.verifyEqual(mod(diff(validIds), cfg.superframeLength), ...
                ones(numel(validIds)-1, 1));
        end
    end

    methods (Static, Access=private)
        function cfg = fastConfiguration(modulationOrder)
            if nargin < 1
                cfg = otfs_tr_config();
            else
                cfg = otfs_tr_config(modulationOrder);
            end
            cfg.enableFractionalTimingCompensation = false;
            cfg.superframeLength = 8;
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
            cfg.totalUniquePayloadBits = cfg.superframeLength* ...
                cfg.effectiveBitsPerFrame;
        end


        function [referenceFile, captureFile] = ...
                createSavedPair(cfg, tempRoot, cfoHz)
            cfg.resultRoot = tempRoot;
            % The simulated baseband offset is fTX-fRX, while the request
            % convention is fRX-fTX.
            cfg = otfs_tr_apply_equivalent_cfo(cfg, -cfoHz);
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
            equivalentDopplerHz = -cfoHz;
            referenceFile = fullfile(tempRoot, "reference_package.mat");
            captureFile = fullfile(tempRoot, "rx_capture.mat");
            save(referenceFile, "cfg", "params", "training", ...
                "reference", "txStatus");
            save(captureFile, "cfg", "rx20", "radioStatus", ...
                "equivalentDopplerHz");
        end


        function txSignal = addPayloadOffset(txSignal, cfg, offset)
            frameLength = cfg.frameLength10;
            for frameIndex = 1:cfg.txBufferFrameCount
                firstPayloadSample = (frameIndex-1)*frameLength + ...
                    cfg.preambleLen+1;
                lastPayloadSample = frameIndex*frameLength;
                txSignal(firstPayloadSample:lastPayloadSample) = ...
                    txSignal(firstPayloadSample:lastPayloadSample)+offset;
            end
        end
    end
end
