from pathlib import Path
import fastq_aligner.metadata_manager
import numpy as np
import polars as pl


def process_metadata():
    metadata_files = {}
    metadata_dir = Path("../metadata")
    assert metadata_dir.exists() and metadata_dir.is_dir()

    for i, dataset_dir in enumerate(sorted(list(metadata_dir.iterdir()))):
        # EGAD00001006630 is clinical data; EGAD00001006741 and EGAD00001007585 are RData files
        if dataset_dir.name in ["EGAD00001006630", "EGAD00001006741", "EGAD00001007585"]:
            continue
        meta_man = fastq_aligner.metadata_manager.MetadataManager(dataset_dir.name, metadata_dir="../metadata")
        meta_man.load_all_tables()
        meta_man.validate_all()
        print(dataset_dir.name)
        #pprint(meta_man.get_validation_report())

        sample_to_files = meta_man.get_sample_to_files_mapping()
        sample_to_library = meta_man.get_sample_to_library_prep_mapping()

        assert np.all(len(v)==2 for v in sample_to_files.values())
        assert np.all(v in ["GENOMIC", "TRANSCRIPTOMIC"] for v in sample_to_library.values())

        files = pl.DataFrame({
            "sample": list(sample_to_files.keys()),
            "file_1": [v[0] if len(v) > 0 else None for v in sample_to_files.values()],
            "file_2": [v[1] if len(v) > 1 else None for v in sample_to_files.values()]
        }).sort("sample")

        library = pl.DataFrame(
            list(sample_to_library.items()), orient="row", schema=["sample", "library"]
        ).sort("sample")

        assert np.all((files.select("sample")==library.select("sample")))

        df = files.join(library, on="sample")
        metadata_filepath = Path(f"../samples/{dataset_dir.name}-samples.csv")
        df.write_csv(metadata_filepath, separator=",", include_header=False)
        metadata_files[dataset_dir.name] = metadata_filepath

    return metadata_files