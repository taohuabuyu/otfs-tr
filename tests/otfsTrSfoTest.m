classdef otfsTrSfoTest < matlab.unittest.TestCase
    %otfsTrSfoTest Tests for continuous-preamble SFO compensation.

    properties (TestParameter)
        sfoCase = struct("positive80ppm", 80, "negative80ppm", -80)
    end

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testDisabledPathPreservesSamples(testCase)
            [rx20, preamble10, params, cfg] = ...
                otfsTrSfoTest.createNominalCapture();
            cfg.enableSfoCompensation = false;

            [actual, info] = otfs_tr_correct_sfo( ...
                rx20, preamble10, params, cfg);

            testCase.verifyEqual(actual, rx20);
            testCase.verifyFalse(info.applied);
            testCase.verifyEqual(info.status, "disabled");
        end

        function testZeroSfoDoesNotResample(testCase)
            [rx20, preamble10, params, cfg] = ...
                otfsTrSfoTest.createNominalCapture();

            [actual, info] = otfs_tr_correct_sfo( ...
                rx20, preamble10, params, cfg);

            testCase.verifyEqual(actual, rx20);
            testCase.verifyFalse(info.applied);
            testCase.verifyLessThan(abs(info.estimatedPpm), ...
                cfg.sfoMinCorrectionPpm);
        end

        function testEstimatesAndCorrectsSignedSfo(testCase, sfoCase)
            [rx20, preamble10, params, cfg] = ...
                otfsTrSfoTest.createNominalCapture();
            distorted = otfsTrSfoTest.injectSfo(rx20, sfoCase);

            [corrected, info] = otfs_tr_correct_sfo( ...
                distorted, preamble10, params, cfg);

            testCase.verifyTrue(info.applied);
            testCase.verifyEqual(info.estimatedPpm, sfoCase, AbsTol=3);
            testCase.verifyEqual(info.observedSamplesPerFrame/info.scale, ...
                info.expectedSamplesPerFrame, AbsTol=1e-9);
            testCase.verifyLessThan(abs(numel(corrected)-numel(rx20)), 5);
        end

        function testEndToEndRecoveryWithSfoAndCfo(testCase)
            [rx20, preamble10, params, cfg] = ...
                otfsTrSfoTest.createNominalCapture();
            [~, reference] = otfs_tr_build_waveform(cfg);
            distorted = otfsTrSfoTest.injectSfo(rx20, 80);
            n = (0:numel(distorted)-1).';
            distorted = distorted .* exp(1j*2*pi*600125/cfg.fsRx*n);
            cfg.maxDecodedFrames = 6;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 250;
            cfg.frameResidualCfoSearchHz = 0;

            processed = wide_rx_process_capture(distorted, ...
                struct("preamble10", preamble10), params, ...
                reference.bitsPerFrame, cfg);
            result = otfs_tr_finalize_result(processed, 600125, cfg);

            testCase.verifyTrue(result.sfoInfo.applied);
            testCase.verifyEqual(result.sfoInfo.estimatedPpm, 80, AbsTol=3);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
            testCase.verifyEqual(result.totalErrors, 0);
        end
    end

    methods (Static, Access=private)
        function [rx20, preamble10, params, cfg] = createNominalCapture()
            cfg = otfs_tr_config();
            cfg.txBufferFrameCount = 32;
            cfg.txBurstLength = cfg.txBufferFrameCount*cfg.frameLength10;
            cfg.sfoMinimumPreambles = 12;
            [txSignal, ~, params, training] = ...
                otfs_tr_build_waveform(cfg);
            rx20 = resample(txSignal, cfg.fsRx/cfg.fsTx, 1);
            preamble10 = training.preamble10;
        end

        function distorted = injectSfo(rx20, sfoPpm)
            scale = 1+sfoPpm*1e-6;
            outputLength = floor((numel(rx20)-1)*scale)+1;
            query = 1+(0:outputLength-1).'/scale;
            distorted = interp1((1:numel(rx20)).', rx20, query, ...
                "linear");
        end
    end
end
