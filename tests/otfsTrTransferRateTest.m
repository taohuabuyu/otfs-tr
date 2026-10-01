classdef otfsTrTransferRateTest < matlab.unittest.TestCase
    %otfsTrTransferRateTest Tests received-bit transfer-rate calculation.

    methods (Test)
        function testUsesSavedReceiveDuration(testCase)
            radioStatus = struct("captureDurationSeconds", 0.2, ...
                "totalReceivedSamples", 4e6);

            [actualRate, actualDuration] = ...
                otfs_tr_calculate_transfer_rate(1e6, radioStatus, 20e6);

            testCase.verifyEqual(actualDuration, 0.2, AbsTol=1e-12);
            testCase.verifyEqual(actualRate, 5e6, AbsTol=1e-6);
        end

        function testDerivesDurationFromReceivedSamples(testCase)
            radioStatus = struct("totalReceivedSamples", 2.4e6);

            [actualRate, actualDuration] = ...
                otfs_tr_calculate_transfer_rate(1.2e6, radioStatus, 20e6);

            testCase.verifyEqual(actualDuration, 0.12, AbsTol=1e-12);
            testCase.verifyEqual(actualRate, 10e6, AbsTol=1e-6);
        end

        function testMissingDurationReturnsUnavailable(testCase)
            radioStatus = struct();

            [actualRate, actualDuration] = ...
                otfs_tr_calculate_transfer_rate(1e6, radioStatus, 20e6);

            testCase.verifyTrue(isnan(actualDuration));
            testCase.verifyTrue(isnan(actualRate));
        end
    end
end
