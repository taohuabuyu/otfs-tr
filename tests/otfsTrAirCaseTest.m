classdef otfsTrAirCaseTest < matlab.unittest.TestCase
    %otfsTrAirCaseTest Air case-code selection without radio hardware.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (TestMethodSetup)
        function setSeed(testCase)
            oldState = rng;
            testCase.addTeardown(@() rng(oldState));
            rng(9, "twister");
        end
    end

    methods (Test)
        function testCaseCodeHeaderRoundTrip(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            caseCode = otfs_tr_case_code("CASE-B");

            mapped = otfs_tr_encode_frame_header(3, cfg, caseCode);
            [frameId, valid, ~, decodedCode] = ...
                otfs_tr_decode_frame_header(mapped, cfg);

            testCase.verifyTrue(valid);
            testCase.verifyEqual(frameId, 3);
            testCase.verifyEqual(decodedCode, caseCode);
        end

        function testCorruptHeaderIsRejected(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            mapped = otfs_tr_encode_frame_header(3, cfg, ...
                otfs_tr_case_code("CASE-B"));
            mapped(1:2) = ~mapped(1:2);

            [~, valid] = otfs_tr_decode_frame_header(mapped, cfg);

            testCase.verifyFalse(valid);
        end

        function testCatalogSelectsCaseFromReceivedSignal(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            caseDirectory = otfsTrAirCaseTest.newDirectory(testCase, cfg);
            otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "a.mat", "CASE-A", cfg);
            secondFile = otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "b.mat", "CASE-B", cfg);
            [rx20, request] = otfsTrAirCaseTest.receivedSignal( ...
                cfg, secondFile);

            selected = otfs_tr_identify_test_case( ...
                rx20, cfg, caseDirectory);
            result = otfs_tr_simulate_link(cfg, -600e3, Inf, request);

            testCase.verifyEqual(selected.filePath, secondFile);
            testCase.verifyEqual(selected.caseId, "CASE-B");
            testCase.verifyEqual(selected.caseCode, ...
                otfs_tr_case_code("CASE-B"));
            testCase.verifyGreaterThanOrEqual( ...
                selected.confirmingFrames, 2);
            testCase.verifyEqual(result.totalErrors, 0);
        end

        function testUnknownAirCodeIsRejected(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            root = otfsTrAirCaseTest.newDirectory(testCase, cfg);
            caseDirectory = fullfile(root, "catalog");
            mkdir(caseDirectory);
            otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "a.mat", "CASE-A", cfg);
            otherFile = otfsTrAirCaseTest.writeCase( ...
                root, "other.mat", "CASE-OTHER", cfg);
            rx20 = otfsTrAirCaseTest.receivedSignal(cfg, otherFile);

            testCase.verifyError( ...
                @() otfs_tr_identify_test_case( ...
                rx20, cfg, caseDirectory), ...
                "otfs_tr:UnknownAirCaseCode");
        end

        function testDuplicateCaseCodesAreRejected(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            caseDirectory = otfsTrAirCaseTest.newDirectory(testCase, cfg);
            otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "a.mat", "CASE-A", cfg);
            otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "b.mat", "CASE-A", cfg);

            testCase.verifyError( ...
                @() otfs_tr_identify_test_case( ...
                zeros(2, 1), cfg, caseDirectory), ...
                "otfs_tr:DuplicateAirCaseCode");
        end

        function testWrongReferenceDoesNotProduceBer(testCase)
            cfg = otfsTrAirCaseTest.fastConfiguration();
            caseDirectory = otfsTrAirCaseTest.newDirectory(testCase, cfg);
            firstFile = otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "a.mat", "CASE-A", cfg);
            secondFile = otfsTrAirCaseTest.writeCase( ...
                caseDirectory, "b.mat", "CASE-B", cfg);
            [rx20, ~] = otfsTrAirCaseTest.receivedSignal( ...
                cfg, secondFile);
            wrongRequest = otfsTrAirCaseTest.request(firstFile);
            [~, wrongReference, params, training] = ...
                otfs_tr_build_waveform(cfg, wrongRequest);

            processed = wide_rx_process_capture( ...
                rx20, training, params, wrongReference, cfg);

            testCase.verifyGreaterThan( ...
                processed.caseCodeMismatches, 0);
            testCase.verifyEqual(processed.validFrames, 0);
            testCase.verifyFalse(processed.referenceAlignmentPass);
        end
    end

    methods (Static, Access=private)
        function cfg = fastConfiguration()
            cfg = otfs_tr_apply_test_case_mode(otfs_tr_config());
            cfg.superframeLength = 8;
            cfg.txBufferFrameCount = 8;
            cfg.txBurstLength = 8*cfg.frameLength10;
            cfg.rxSamplesPerFrame = 8*cfg.frameLength10*cfg.rxSampleRateRatio;
            cfg.availableCaptureFrames = 7;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
            cfg.maxDecodedFrames = 6;
            cfg.totalUniquePayloadBits = ...
                cfg.berTestBitsPerFrame*cfg.superframeLength;
            cfg.enableFractionalTimingCompensation = false;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 500;
            cfg.frameResidualCfoSearchHz = -1000:100:1000;
        end

        function directory = newDirectory(testCase, cfg)
            directory = string(tempname(cfg.resultRoot));
            mkdir(directory);
            testCase.addTeardown(@() rmdir(directory, "s"));
        end

        function filePath = writeCase(directory, name, caseId, cfg)
            filePath = string(fullfile(directory, name));
            test_case = struct("version", 1, "case_id", caseId, ...
                "payload_bits", uint8(randi([0, 1], ...
                cfg.berTestBitsPerFrame, cfg.superframeLength)));
            save(filePath, "test_case");
        end

        function request = request(filePath)
            request = struct("test_case_file", filePath, ...
                "equivalent_cfo_hz", 600e3);
        end

        function [rx20, request] = receivedSignal(cfg, filePath)
            request = otfsTrAirCaseTest.request(filePath);
            txSignal = otfs_tr_build_waveform(cfg, request);
            rx20 = resample(txSignal, cfg.rxSampleRateRatio, 1);
            n = (0:numel(rx20)-1).';
            rx20 = rx20 .* exp(-1j*2*pi*600e3/cfg.fsRx*n);
        end
    end
end
