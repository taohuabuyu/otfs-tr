classdef otfsTrCumulativeTest < matlab.unittest.TestCase
    %otfsTrCumulativeTest Verify BER accumulation across short captures.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testAccumulatesOnlyUniqueFrameIds(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.superframeLength = 8;
            cfg.minimumTestBits = 6;
            stateDirectory = testCase.createProjectTempDirectory();
            stateFile = fullfile(stateDirectory, "cumulative.mat");
            first = otfsTrCumulativeTest.resultForFrames( ...
                [0 1], {[false; false], [false; true]}, "run-1");
            second = otfsTrCumulativeTest.resultForFrames( ...
                [1 2], {[true; true], [false; false]}, "run-2");

            % Act.
            otfs_tr_accumulate_results(stateFile, first, cfg);
            cumulative = otfs_tr_accumulate_results( ...
                stateFile, second, cfg);

            % Assert.
            testCase.verifyEqual(cumulative.batchCount, 2);
            testCase.verifyEqual(cumulative.validFrames, 3);
            testCase.verifyEqual(cumulative.testedBits, 6);
            testCase.verifyEqual(cumulative.bitErrors, 1);
            testCase.verifyEqual(cumulative.duplicatesSkipped, 1);
            testCase.verifyEqual(cumulative.newValidFrames, 1);
            testCase.verifyEqual(cumulative.ber, 1/6, AbsTol=0);
            testCase.verifyTrue(cumulative.targetReached);
            testCase.verifyTrue(isfile(cumulative.jsonFile));
        end

        function testRejectsLegacyRepeatedReference(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            stateDirectory = testCase.createProjectTempDirectory();
            stateFile = fullfile(stateDirectory, "cumulative.mat");
            result = otfsTrCumulativeTest.resultForFrames( ...
                0, {[false; false]}, "run-1");
            result.referenceMode = "legacy-repeated";

            % Act.
            operation = @() otfs_tr_accumulate_results( ...
                stateFile, result, cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:CumulativeBerRequiresUniqueFrames");
        end
    end

    methods (Access=private)
        function directory = createProjectTempDirectory(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            directory = string(tempname(fullfile(projectRoot, "results")));
            mkdir(directory);
            testCase.addTeardown(@() rmdir(directory, "s"));
        end
    end

    methods (Static, Access=private)
        function result = resultForFrames(frameIds, errors, runId)
            frameIds = frameIds(:);
            diagnostics = repmat(struct("bitErrors", false(0, 1)), ...
                numel(frameIds), 1);
            for index = 1:numel(frameIds)
                diagnostics(index).bitErrors = logical(errors{index});
            end
            result = struct("referenceMode", "unique-superframe", ...
                "frameIds", frameIds, ...
                "frameBer", zeros(numel(frameIds), 1), ...
                "frameDiagnostics", diagnostics, ...
                "localRunId", runId);
        end
    end
end
