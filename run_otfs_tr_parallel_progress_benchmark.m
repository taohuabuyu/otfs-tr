function benchmark = run_otfs_tr_parallel_progress_benchmark( ...
        pairDirectory, workerCounts, mpMaximumIterations)
%run_otfs_tr_parallel_progress_benchmark Compare full offline runs.

if nargin < 1 || strlength(string(pairDirectory)) == 0
    cfg = otfs_tr_config();
    [pairDirectory, ~, ~] = otfs_tr_find_latest_pair(cfg.resultRoot);
end
if nargin < 2 || isempty(workerCounts)
    workerCounts = [12 16];
end
if nargin < 3
    mpMaximumIterations = [];
end

pairDirectory = string(pairDirectory);
referenceFile = fullfile(pairDirectory, "tx", "reference_package.mat");
captureFile = fullfile(pairDirectory, "rx", "rx_capture.mat");
if ~isfile(referenceFile) || ~isfile(captureFile)
    error("otfs_tr:IncompletePair", ...
        "Benchmark input must be a complete saved TX/RX pair: %s", ...
        pairDirectory);
end

timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
benchmarkDirectory = fullfile(fileparts(fileparts(pairDirectory)), ...
    "parallel_progress_benchmark_" + timestamp);
mkdir(benchmarkDirectory);
benchmarkFile = fullfile(benchmarkDirectory, "benchmark_summary.mat");
records = repmat(localEmptyRecord(), numel(workerCounts), 1);

for index = 1:numel(workerCounts)
    workerCount = workerCounts(index);
    pool = gcp("nocreate");
    if ~isempty(pool)
        delete(pool);
    end

    tx = load(referenceFile);
    tx.cfg.enableFrameParallel = true;
    tx.cfg.frameParallelWorkers = workerCount;
    tx.cfg.frameParallelMinimumFrames = 2;
    tx.cfg.enableProgressReporting = true;
    tx.cfg.progressFile = string(fullfile(benchmarkDirectory, ...
        "progress_" + workerCount + "_workers.json"));
    tx.cfg.progressUpdateEveryFrames = 10;
    tx.cfg.progressMinimumIntervalSeconds = 0.5;
    if ~isempty(mpMaximumIterations)
        tx.cfg.mpMaximumIterations = mpMaximumIterations;
    end
    tx.cfg.resultRoot = fullfile(benchmarkDirectory, ...
        workerCount + "_workers");
    benchmarkReferenceFile = fullfile(benchmarkDirectory, ...
        "reference_" + workerCount + "_workers.mat");
    save(benchmarkReferenceFile, "-struct", "tx", "-v7.3");

    fprintf("Starting %d-worker DataQueue/progress benchmark.\n", ...
        workerCount);
    runTimer = tic;
    result = run_otfs_tr_offline_decode( ...
        benchmarkReferenceFile, captureFile);
    elapsedSeconds = toc(runTimer);

    records(index).requestedWorkers = workerCount;
    records(index).mpMaximumIterations = ...
        tx.cfg.mpMaximumIterations;
    records(index).actualWorkers = ...
        result.frameParallelInfo.actualWorkers;
    records(index).elapsedSeconds = elapsedSeconds;
    records(index).detectionElapsedSeconds = ...
        result.frameParallelInfo.detectionElapsedSeconds;
    records(index).progressWriteCount = ...
        result.frameParallelInfo.progressWriteCount;
    records(index).progressUpdateIntervalsSeconds = ...
        result.frameParallelInfo.progressUpdateIntervalsSeconds;
    records(index).progressFile = tx.cfg.progressFile;
    records(index).reportDirectory = result.report.directory;
    records(index).validFrames = result.validFrames;
    records(index).totalBits = result.totalBits;
    records(index).totalErrors = result.totalErrors;
    records(index).ber = result.ber;
    records(index).cfoEstimateHz = result.cfoEstimateHz;
    benchmark = localBuildBenchmark( ...
        pairDirectory, benchmarkDirectory, records, index);
    save(benchmarkFile, "benchmark");
    fprintf(['Completed %d workers: total %.3f s, detection %.3f s, ' ...
        'progress writes %d.\n'], workerCount, elapsedSeconds, ...
        records(index).detectionElapsedSeconds, ...
        records(index).progressWriteCount);
end

pool = gcp("nocreate");
if ~isempty(pool)
    delete(pool);
end
benchmark = localBuildBenchmark(pairDirectory, ...
    benchmarkDirectory, records, numel(records));
save(benchmarkFile, "benchmark");
fprintf("Benchmark summary: %s\n", benchmarkFile);
end

function benchmark = localBuildBenchmark( ...
        pairDirectory, benchmarkDirectory, records, completedRuns)
benchmark = struct();
benchmark.pairDirectory = pairDirectory;
benchmark.benchmarkDirectory = string(benchmarkDirectory);
benchmark.completedRuns = completedRuns;
benchmark.records = records;
benchmark.createdAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
end

function record = localEmptyRecord()
record = struct("requestedWorkers", NaN, "actualWorkers", NaN, ...
    "mpMaximumIterations", NaN, ...
    "elapsedSeconds", NaN, "detectionElapsedSeconds", NaN, ...
    "progressWriteCount", NaN, ...
    "progressUpdateIntervalsSeconds", zeros(0, 1), ...
    "progressFile", "", "reportDirectory", "", ...
    "validFrames", NaN, "totalBits", NaN, "totalErrors", NaN, ...
    "ber", NaN, "cfoEstimateHz", NaN);
end
