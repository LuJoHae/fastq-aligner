import fastq_aligner
from pathlib import Path
from pprint import pprint
import remote_slurm.slurmify
import polars as pl
import numpy as np
from returns.result import Success, Failure
import logging
import fastq_aligner.utils


def run_validation(dataset_id = "EGAD00001004183"):
    slurm_opts = remote_slurm.slurmify.SlurmOptions(
        job_name="validate",
        partition="debug",
        time="00:00:10",
        output="/users/%u/log/%x-%j/log.out",
        error="/users/%u/log/%x-%j/log.err",
        mail_user="lukas.haeuser@empa.ch",
        mail_type="BEGIN,END,FAIL"
    )
    script_validate_path = Path("../scripts/validate_fastq_file_existence.sh")
    slurm_script = remote_slurm.slurmify.SlurmScript(slurm_opts, script_validate_path)
    ssh_connection = remote_slurm.ssh.SSHConnection("eiger")
    remote_sample_file_path = Path("/capstor/scratch/cscs/lhaeuser/tmp/samples.csv")
    args = f"{remote_sample_file_path} /capstor/scratch/cscs/lhaeuser/{dataset_id}"
    slurm_executor = remote_slurm.execute.SlurmExecutor(ssh_connection, slurm_script, args)
    ssh_connection.copy_to_remote(f"../samples/{dataset_id}-samples.csv", str(remote_sample_file_path))
    submitted_job = slurm_executor.execute()
    return submitted_job


def run_transcriptome_alignments(metadata_files):

    slurm_opts = remote_slurm.slurmify.SlurmOptions(
        job_name= "align-transcriptome",
        partition="normal",
        time="12:00:00",
        output="/users/%u/log/align-transcriptome-%A/star_align_%A_%a.out",
        error="/users/%u/log/align-transcriptome-%A/star_align_%A_%a.err",
        mail_user="lukas.haeuser@empa.ch",
        mail_type="BEGIN,END,FAIL",
        mem="200G"
    )
    print(slurm_opts)

    script_align_path = Path("../scripts/align_transcriptomics.sh")
    ssh_connection = remote_slurm.ssh.SSHConnection("eiger")
    submitted_jobs = dict()
    for dataset_id, csv_filepath in metadata_files.items():
        if dataset_id not in ["EGAD00001003977", "EGAD00001004183", "EGAD00001006631"]:
            continue
        remote_sample_file_path = Path(f"/capstor/scratch/cscs/lhaeuser/tmp/{dataset_id}-samples.csv")
        args = f"--csv {str(remote_sample_file_path)}\
        --data-dir /capstor/scratch/cscs/lhaeuser/{dataset_id}\
        --gtf /capstor/scratch/cscs/lhaeuser/STAR/download/genes-115.gtf\
        --genome /capstor/scratch/cscs/lhaeuser/STAR/download/GRCh38.fa\
        --star-index /capstor/scratch/cscs/lhaeuser/STAR/star_index\
        --output /capstor/scratch/cscs/lhaeuser/{dataset_id}-align"
        sample_filepath = Path(f"../samples/{dataset_id}-samples.csv")
        linecount = fastq_aligner.utils.get_line_count(sample_filepath)
        slurm_opts.array = f"1-{linecount}%200"
        slurm_script = remote_slurm.slurmify.SlurmScript(slurm_opts, script_align_path)
        slurm_executor = remote_slurm.execute.SlurmExecutor(ssh_connection, slurm_script, args)
        ssh_connection.copy_to_remote(str(sample_filepath), str(remote_sample_file_path))
        submitted_jobs[dataset_id] = slurm_executor.execute()
    return submitted_jobs
