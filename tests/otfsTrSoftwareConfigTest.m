classdef otfsTrSoftwareConfigTest < matlab.unittest.TestCase
    %otfsTrSoftwareConfigTest Non-hardware TXT-to-MAT-bit transmit tests.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testDirectReceiverCaseKeepsCfoUnknown(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            cfg.resultRoot = string(tempdir);
            [caseFile, ~] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);

            options = otfs_tr_resolve_receiver_input(caseFile);

            testCase.verifyTrue(options.localTestCaseMode);
            testCase.verifyFalse(options.softwareTxtMode);
            testCase.verifyFalse(options.requestedCfoKnown);
            testCase.verifyTrue(isnan(options.equivalentDopplerHz));
            testCase.verifyEqual(options.testCaseInput, caseFile);
        end

        function testReceiverRejectsNumericCfo(testCase)
            testCase.verifyError( ...
                @() otfs_tr_resolve_receiver_input(-600e3), ...
                "otfs_tr:InvalidReceiverInput");
        end

        function testTransmitterDoesNotGenerateCfoReceiverCommand(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            txText = fileread(fullfile(projectRoot, ...
                "run_otfs_tr_transmitter.m"));

            testCase.verifyFalse(contains(txText, ...
                "run_otfs_tr_receiver(%+.0f)"));
            testCase.verifyTrue(contains(txText, ...
                'run_otfs_tr_receiver("<RX_LOCAL_TEST_CASE_MAT>")'));
        end

        function testRxConfigAcceptsRelativeMatPathWithoutCfo(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);
            [~, caseName, extension] = fileparts(caseFile);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, "testPayload=" + caseName + extension, "UTF-8");

            rxConfig = otfs_tr_load_receiver_config(configFile);

            testCase.verifyEqual(rxConfig.test_case_file, caseFile);
            testCase.verifyFalse(isfield(rxConfig, "equivalent_cfo_hz"));
        end

        function testRxConfigRejectsTransmitterCfo(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);
            content = "testPayload=" + caseFile + newline + ...
                "freq_offset_hz=600000";
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "UTF-8");

            testCase.verifyError( ...
                @() otfs_tr_load_receiver_config(configFile), ...
                "otfs_tr:UnsupportedSoftwareConfigKey");
        end

        function testRxConfigRequiresTestCasePath(testCase)
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, "# reference is required", "UTF-8");

            testCase.verifyError( ...
                @() otfs_tr_load_receiver_config(configFile), ...
                "otfs_tr:MissingRxTestCasePath");
        end

        function testRxLocalDecodeEstimatesUnknownCfo(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            cfg.enableFractionalTimingCompensation = false;
            cfg.maxDecodedFrames = 6;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 500;
            cfg.frameResidualCfoSearchHz = -1000:100:1000;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
            [caseFile, ~] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);
            tempRoot = string(tempname(cfg.resultRoot));
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));
            cfg.resultRoot = tempRoot;
            pair = otfs_tr_prepare_pair(cfg);
            referenceFile = otfs_tr_prepare_local_reference( ...
                cfg, NaN, caseFile, pair);
            saved = load(referenceFile, "reference");
            txSignal = saved.reference.txSuperframe;
            rx20 = resample(txSignal, cfg.rxSampleRateRatio, 1);
            sampleIndex = (0:numel(rx20)-1).';
            rx20 = rx20 .* exp(1j*2*pi*600e3/cfg.fsRx*sampleIndex);
            radioStatus = struct("captureCalls", 1, ...
                "anyRxOverrun", false, "captureComplete", true, ...
                "totalReceivedSamples", numel(rx20));
            equivalentDopplerHz = NaN;
            requestedCfoKnown = false;
            save(pair.captureFile, "cfg", "rx20", "radioStatus", ...
                "equivalentDopplerHz", "requestedCfoKnown");

            result = run_otfs_tr_offline_decode(pair.pairDirectory);

            testCase.verifyFalse(result.requestedCfoKnown);
            testCase.verifyEqual(result.cfoAssessmentSource, "estimated_cfo");
            testCase.verifyEqual(result.cfoEstimateHz, 600e3, AbsTol=100);
            testCase.verifyEqual(result.localRunId, pair.runId);
            testCase.verifyTrue(result.acceptance.dopplerPass);
            testCase.verifyEqual( ...
                result.softwareResponse.metrics.cfo_assessment_source, ...
                "estimated_cfo");
        end

        function testRxLocalReferenceUsesSavedCaseBits(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, expectedBits] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);
            tempRoot = string(tempname(cfg.resultRoot));
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));
            cfg.resultRoot = tempRoot;
            pair = otfs_tr_prepare_pair(cfg);

            referenceFile = otfs_tr_prepare_local_reference( ...
                cfg, 600e3, caseFile, pair);
            saved = load(referenceFile, "reference", "txStatus", ...
                "referenceOrigin", "request");

            testCase.verifyEqual(saved.reference.berTestBitsByFrame, ...
                double(expectedBits));
            testCase.verifyEqual(saved.reference.testCase.caseId, ...
                "CASE-001");
            testCase.verifyEqual(saved.referenceOrigin, ...
                "rx-local-test-case");
            testCase.verifyFalse(saved.txStatus.started);
            testCase.verifyFalse(saved.txStatus.completed);
        end

        function testGbkConfigResolvesMatAndTunesTx(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            content = sprintf([ ...
                'testPayload=%s\r\nscenario=宽频带频偏\r\n' ...
                'freq_offset_hz=500000\r\ntargetBer=1e-05\r\n' ...
                'targetSpectralEfficiency=1.5\r\n'], caseFile);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "GBK");

            request = otfs_tr_load_software_config(configFile);
            configured = otfs_tr_apply_test_case_mode(otfs_tr_config());
            configured = otfs_tr_apply_equivalent_cfo( ...
                configured, request.equivalent_cfo_hz);
            configured = otfs_tr_apply_software_targets( ...
                configured, request);

            testCase.verifyEqual(request.test_case_file, caseFile);
            testCase.verifyFalse(isfield(request, "payload_text"));
            testCase.verifyEqual(request.scenario_name, "宽频带频偏");
            testCase.verifyEqual(configured.txCenterFrequencyHz, ...
                2.6745e9, AbsTol=1e-6);
            testCase.verifyEqual(configured.rxCenterFrequencyHz, ...
                2.675e9, AbsTol=1e-6);
            testCase.verifyEqual(configured.berTestBitsPerFrame, 1881);
            testCase.verifyEqual(configured.minimumValidFrames, 532);
            testCase.verifyEqual(configured.maxDecodedFrames, 586);
            testCase.verifyEqual(configured.minimumSpectralEfficiency, ...
                2, AbsTol=1e-12);
            testCase.verifyWarningFree( ...
                @() otfs_tr_validate_config(configured));
        end

        function testRelativeMatPathUsesTxtDirectory(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            [~, caseName, extension] = fileparts(caseFile);
            content = sprintf('testPayload=%s%s\nfreq_offset_hz=-600000\n', ...
                caseName, extension);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "UTF-8");

            request = otfs_tr_load_software_config(configFile);

            testCase.verifyEqual(request.test_case_file, caseFile);
            testCase.verifyEqual(request.equivalent_cfo_hz, ...
                -600e3, AbsTol=1e-6);
        end

        function testMatBitsBecomeEntireWaveformPayload(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, expectedBits] = ...
                otfsTrSoftwareConfigTest.writeTestCase(testCase, cfg);
            content = sprintf('testPayload=%s\nfreq_offset_hz=600000\n', ...
                caseFile);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "UTF-8");
            request = otfs_tr_load_software_config(configFile);

            [txSignal, reference, params] = otfs_tr_build_waveform( ...
                cfg, request);

            testCase.verifyEqual(reference.payloadBitsByFrame, ...
                double(expectedBits));
            testCase.verifyEqual(reference.berTestBitsByFrame, ...
                double(expectedBits));
            testCase.verifyEqual(reference.bits, double(expectedBits(:)));
            testCase.verifyEqual(reference.testCase.caseId, "CASE-001");
            testCase.verifyEqual(params.applicationMappedBitsPerFrame, 0);
            testCase.verifyFalse(reference.application.enabled);
            testCase.verifyGreaterThan(numel(txSignal), 0);
        end

        function testIdealLinkRecoversMatBits(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            cfg.enableFractionalTimingCompensation = false;
            cfg.maxDecodedFrames = 6;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 500;
            cfg.frameResidualCfoSearchHz = -1000:100:1000;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            request = struct("test_case_file", caseFile, ...
                "equivalent_cfo_hz", 600e3);

            result = otfs_tr_simulate_link(cfg, 600e3, Inf, request);

            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyGreaterThan(result.validFrames, 0);
            testCase.verifyEqual(result.totalBits, ...
                result.validFrames*cfg.berTestBitsPerFrame);
        end

        function testRejectsOldAaaTextAsFilePath(testCase)
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, "testPayload=AAA" + newline + ...
                "freq_offset_hz=500000", "UTF-8");

            testCase.verifyError( ...
                @() otfs_tr_load_software_config(configFile), ...
                "otfs_tr:MissingTestCaseFile");
        end

        function testRejectsMalformedMatBits(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            saved = load(caseFile, "test_case");
            test_case = saved.test_case;
            test_case.payload_bits(1, 1) = 2;
            save(caseFile, "test_case");

            testCase.verifyError( ...
                @() otfs_tr_load_test_case(caseFile, cfg), ...
                "otfs_tr:InvalidTestCaseBits");
        end

        function testRejectsWrongMatDimensions(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            saved = load(caseFile, "test_case");
            test_case = saved.test_case;
            test_case.payload_bits = test_case.payload_bits(1:end-1, :);
            save(caseFile, "test_case");

            testCase.verifyError( ...
                @() otfs_tr_load_test_case(caseFile, cfg), ...
                "otfs_tr:InvalidTestCaseBits");
        end

        function testRejectsDuplicateTxtKey(testCase)
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, sprintf( ...
                'freq_offset_hz=600000\nfreq_offset_hz=-600000\n'), ...
                "UTF-8");

            testCase.verifyError( ...
                @() otfs_tr_load_software_config(configFile), ...
                "otfs_tr:DuplicateSoftwareConfigKey");
        end

        function testRejectsOutOfRangeFrequency(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            content = sprintf('testPayload=%s\nfreq_offset_hz=900000\n', ...
                caseFile);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "UTF-8");

            testCase.verifyError( ...
                @() otfs_tr_load_software_config(configFile), ...
                "otfs_tr:InvalidRequestedCfo");
        end

        function testRequestedTargetsCannotWeakenProjectLimits(testCase)
            cfg = otfsTrSoftwareConfigTest.smallConfiguration();
            [caseFile, ~] = otfsTrSoftwareConfigTest.writeTestCase( ...
                testCase, cfg);
            content = sprintf([ ...
                'testPayload=%s\nfreq_offset_hz=600000\n' ...
                'targetBer=0.001\ntargetSpectralEfficiency=1.5\n'], ...
                caseFile);
            configFile = otfsTrSoftwareConfigTest.writeConfig( ...
                testCase, content, "UTF-8");
            request = otfs_tr_load_software_config(configFile);

            configured = otfs_tr_apply_software_targets( ...
                otfs_tr_apply_test_case_mode(otfs_tr_config()), request);

            testCase.verifyEqual(configured.maximumBer, ...
                1e-5, AbsTol=1e-15);
            testCase.verifyEqual(configured.minimumSpectralEfficiency, ...
                2, AbsTol=1e-12);
        end
    end

    methods (Static, Access=private)
        function cfg = smallConfiguration()
            cfg = otfs_tr_apply_test_case_mode(otfs_tr_config());
            cfg.resultRoot = string(tempdir);
            cfg.superframeLength = 8;
            cfg.txBufferFrameCount = 8;
            cfg.totalUniquePayloadBits = cfg.berTestBitsPerFrame * ...
                cfg.superframeLength;
        end

        function [filePath, bits] = writeTestCase(testCase, cfg)
            filePath = string(tempname(cfg.resultRoot)) + ".mat";
            previousRng = rng;
            rng(42, "twister");
            bits = uint8(randi([0, 1], ...
                cfg.berTestBitsPerFrame, cfg.superframeLength));
            rng(previousRng);
            test_case = struct("version", 1, "case_id", "CASE-001", ...
                "payload_bits", bits);
            save(filePath, "test_case");
            testCase.addTeardown(@() delete(filePath));
        end

        function filePath = writeConfig(testCase, content, encoding)
            filePath = string(tempname(tempdir)) + ".txt";
            fileId = fopen(filePath, "wb");
            fwrite(fileId, unicode2native(char(content), encoding), ...
                "uint8");
            fclose(fileId);
            testCase.addTeardown(@() delete(filePath));
        end
    end
end
