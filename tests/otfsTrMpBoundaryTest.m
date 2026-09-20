classdef otfsTrMpBoundaryTest < matlab.unittest.TestCase
    %otfsTrMpBoundaryTest Check MP Doppler-row circular boundaries.

    properties (TestParameter)
        integerDoppler = struct( ...
            "positiveWrap", 1, ...
            "negativeWrap", -1)
    end

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (TestMethodSetup)
        function useDeterministicSymbols(testCase)
            previousState = rng;
            testCase.addTeardown(@() rng(previousState));
            rng(42, "twister");
        end
    end

    methods (Test)
        function testNoDcIntegerDopplerWrapHasNoRowErrors( ...
                testCase, integerDoppler)
            % Arrange: one noiseless integer-Doppler tap with no added DC.
            N = 32;
            M = 24;
            modulationOrder = 8;
            symbolIndices = randi([0 modulationOrder-1], N, M);
            transmittedGrid = qammod(symbolIndices, modulationOrder, ...
                "gray", "UnitAveragePower", true);
            transmittedSamples = OTFS_modulation(N, M, transmittedGrid);
            sampleIndices = (0:N*M-1).';
            receivedSamples = transmittedSamples .* exp( ...
                1j*2*pi*integerDoppler*sampleIndices/(N*M));
            receivedGrid = OTFS_demodulation(N, M, receivedSamples);

            % Act: detect with the exact single integer channel tap.
            detectedGrid = OTFS_MP_Detection(N, M, modulationOrder, ...
                1, 0, integerDoppler, 1, 1e-8, receivedGrid);
            symbolErrors = detectedGrid ~= transmittedGrid;

            % Assert: both circular boundary rows and the full grid decode.
            testCase.verifyEqual(nnz(symbolErrors), 0);
            testCase.verifyEqual(nnz(symbolErrors(1, :)), 0);
            testCase.verifyEqual(nnz(symbolErrors(end, :)), 0);
        end
    end
end
