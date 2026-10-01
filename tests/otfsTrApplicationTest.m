classdef otfsTrApplicationTest < matlab.unittest.TestCase
    %otfsTrApplicationTest Tests for short UTF-8 application transport.

    properties (TestParameter)
        payloadCase = struct("aa", "AA", "ab", "AB", ...
            "unicode", "测试")
    end

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testApplicationPacketRoundTrip(testCase, payloadCase)
            cfg = otfs_tr_config();
            request = otfsTrApplicationTest.request(payloadCase);

            [mappedBits, encoded] = ...
                otfs_tr_encode_application(request, cfg);
            decoded = otfs_tr_decode_application(mappedBits, cfg);

            testCase.verifyEqual(numel(mappedBits), ...
                cfg.applicationMappedBitsPerFrame);
            testCase.verifyTrue(decoded.valid);
            testCase.verifyTrue(decoded.crcPass);
            testCase.verifyEqual(decoded.decodedText, payloadCase);
            testCase.verifyEqual(encoded.transmittedText, payloadCase);
        end

        function testApplicationPacketRejectsCorruption(testCase)
            cfg = otfs_tr_config();
            [mappedBits, ~] = otfs_tr_encode_application( ...
                otfsTrApplicationTest.request("AA"), cfg);
            mappedBits(80) = ~mappedBits(80);

            decoded = otfs_tr_decode_application(mappedBits, cfg);

            testCase.verifyFalse(decoded.valid);
            testCase.verifyFalse(decoded.crcPass);
            testCase.verifyEqual(decoded.errorCode, "CRC_FAILED");
        end

        function testRequestRejectsOversizeUtf8Payload(testCase)
            cfg = otfs_tr_config();
            request = otfsTrApplicationTest.request( ...
                string(repmat('A', 1, 33)));

            operation = @() otfs_tr_validate_request(request, cfg);

            testCase.verifyError(operation, ...
                "otfs_tr:InvalidPayloadLength");
        end

        function testRequestRejectsUnknownOption(testCase)
            cfg = otfs_tr_config();
            request = otfsTrApplicationTest.request("AA");
            request.options = struct("unexpected", 1);

            operation = @() otfs_tr_validate_request(request, cfg);

            testCase.verifyError(operation, ...
                "otfs_tr:UnsupportedRequestOption");
        end

        function testWaveformSeparatesApplicationAndBerBits(testCase)
            cfg = otfsTrApplicationTest.fastConfiguration();
            request = otfsTrApplicationTest.request("AB");

            [~, reference] = otfs_tr_build_waveform(cfg, request);

            testCase.verifyEqual(reference.application.transmittedText, "AB");
            testCase.verifyEqual(reference.effectiveBitsPerFrame, ...
                cfg.berTestBitsPerFrame);
            testCase.verifyEqual(size(reference.berTestBitsByFrame), ...
                [cfg.berTestBitsPerFrame cfg.superframeLength]);
            testCase.verifyEqual(reference.payloadBitsByFrame( ...
                1:cfg.applicationMappedBitsPerFrame, 1), ...
                reference.application.mappedBits);
        end

        function testIdealLinkRestoresApplicationText(testCase)
            cfg = otfsTrApplicationTest.fastConfiguration();
            request = otfsTrApplicationTest.request("AA");

            result = otfs_tr_simulate_link(cfg, 600e3, Inf, request);

            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.application.decodedText, "AA");
            testCase.verifyTrue(result.application.crcPass);
            testCase.verifyTrue(result.application.textMatch);
            testCase.verifyTrue(result.application.pass);
        end

        function testJsonHandlerReturnsStableValidationError(testCase)
            request = struct("protocol_version", "1.0", ...
                "command", "start_test", ...
                "payload_text", "AA", "equivalent_cfo_hz", 900e3);

            response = jsondecode(otfs_tr_handle_json(jsonencode(request)));

            testCase.verifyEqual(response.code, 1006);
            testCase.verifyEqual(string(response.error_code), "INVALID_CFO");
            testCase.verifyEqual(string(response.status), "failed");
        end

    end

    methods (Static, Access=private)
        function request = request(payloadText)
            request = struct("protocol_version", "1.0", ...
                "command", "start_test", ...
                "payload_text", payloadText, ...
                "equivalent_cfo_hz", 600e3, ...
                "options", struct("duration_seconds", 30));
        end

        function cfg = fastConfiguration()
            cfg = otfs_tr_config();
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
    end
end
