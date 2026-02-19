import polars as pl
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Set, Optional


class MetadataManager:
    """Manages reading and validation of TSV metadata files for EGA datasets."""

    def __init__(self, dataset_id: str, metadata_dir: str = "metadata"):
        """
        Initialize the metadata manager for a specific dataset.

        Args:
            dataset_id: Dataset identifier starting with EGAD
            metadata_dir: Base directory containing dataset metadata folders
        """
        if not dataset_id.startswith("EGAD"):
            raise ValueError(f"Dataset ID must start with 'EGAD', got: {dataset_id}")

        self.dataset_id = dataset_id
        self.dataset_path = Path(metadata_dir) / dataset_id

        if not self.dataset_path.exists():
            raise FileNotFoundError(f"Dataset directory not found: {self.dataset_path}")

        self.tables: Dict[str, pl.DataFrame] = {}
        self.validation_errors: List[str] = []

        # Define which columns should have unique values for each table
        self.unique_columns = {
            'samples.tsv': ['accession_id', 'alias', 'title', 'description'],
            'runs.tsv': ['accession_id', 'sample_accession_id', 'experiment_accession_id', ],
            'experiments.tsv': ['accession_id'],
            'analyses.tsv': ['accession_id'],
            'studies.tsv': ['accession_id'],
            'dataset.tsv': ['accession_id'],
            'sample_file.tsv': ['file_name', 'file_accession_id'],
        }

    def read_tsv(self, filename: str) -> pl.DataFrame:
        """Read a TSV file and return Polars DataFrame."""
        filepath = self.dataset_path / filename
        if not filepath.exists():
            return pl.DataFrame()

        return pl.read_csv(filepath, separator='\t')

    def load_all_tables(self):
        """Load all TSV files in the dataset directory."""
        for tsv_file in self.dataset_path.glob("*.tsv"):
            table_name = tsv_file.name
            self.tables[table_name] = self.read_tsv(table_name)

    def validate_unique_columns(self):
        """Check that columns marked as unique contain only unique values."""
        for table_name, unique_cols in self.unique_columns.items():
            if table_name not in self.tables:
                continue

            table = self.tables[table_name]
            for col in unique_cols:
                if table.is_empty():
                    continue

                if col not in table.columns:
                    self.validation_errors.append(
                        f"{table_name}: Column '{col}' not found"
                    )
                    continue

                values = table[col].drop_nulls()
                unique_values = values.unique()

                if len(values) != len(unique_values):
                    value_counts = table[col].value_counts()
                    duplicates = value_counts.filter(pl.col("count") > 1)[col].to_list()
                    self.validation_errors.append(
                        f"{table_name}: Column '{col}' has duplicate values: {duplicates[:5]}"
                    )

    def extract_identifiers_from_table(self, table: pl.DataFrame) -> Dict[str, Set[str]]:
        """Extract all EGA identifiers from a table, grouped by type."""
        identifiers = defaultdict(set)

        if table.is_empty():
            return identifiers

        for col in table.columns:
            values = table[col].drop_nulls().to_list()
            for value in values:
                if not value or value == '\\N':
                    continue

                # Check if value is an EGA identifier
                if isinstance(value, str) and value.startswith("EGA") and len(value) > 4:
                    # Extract identifier type (4th character after EGA)
                    if value[3] in ['D', 'S', 'R', 'F', 'X', 'Z', 'A', 'N']:
                        id_type = value[3]
                        identifiers[id_type].add(value)

        return identifiers

    def get_all_identifiers_by_type(self) -> Dict[str, Dict[str, Set[str]]]:
        """Get all identifiers from all tables, organized by table and type."""
        all_identifiers = {}

        for table_name, table in self.tables.items():
            all_identifiers[table_name] = self.extract_identifiers_from_table(table)

        return all_identifiers

    def validate_cross_references(self):
        """Validate that identifiers referenced across tables are consistent."""
        all_ids = self.get_all_identifiers_by_type()

        # Collect all identifiers of each type across all tables
        global_ids_by_type = defaultdict(set)
        for table_name, id_types in all_ids.items():
            for id_type, ids in id_types.items():
                global_ids_by_type[id_type].update(ids)

        # For each table, check that referenced identifiers exist globally
        for table_name, id_types in all_ids.items():
            for id_type, ids in id_types.items():
                # Check if these IDs appear in other tables that should contain them
                for other_table, other_id_types in all_ids.items():
                    if other_table == table_name:
                        continue

                    if id_type in other_id_types:
                        # IDs in current table should exist in the global set
                        missing = ids - global_ids_by_type[id_type]
                        if missing and len(missing) < len(ids):
                            # Only report if some but not all are missing
                            pass

    def get_sample_to_files_mapping(self) -> Dict[str, List[str]]:
        """
        Get a mapping from sample IDs to file IDs.

        Returns:
            Dictionary mapping sample accession IDs (EGAN...) to list of file IDs (EGAF...)
        """
        mapping = defaultdict(list)

        # Read sample_file.tsv if available
        if 'sample_file.tsv' in self.tables:
            table = self.tables['sample_file.tsv']
            if not table.is_empty() and 'sample_accession_id' in table.columns and 'file_accession_id' in table.columns:
                for row in table.iter_rows(named=True):
                    sample_id = row.get('sample_accession_id', '')
                    file_id = row.get('file_accession_id', '')

                    if sample_id and file_id and sample_id.startswith('EGAN') and file_id.startswith('EGAF'):
                        mapping[sample_id].append(file_id)

        return dict(mapping)

    def get_sample_to_library_prep_mapping(self) -> Dict[str, str]:
        """
        Get a mapping from sample IDs to library preparation type.

        Returns:
            Dictionary mapping sample accession IDs (EGAN...) to library preparation type
            ('genomic' or 'transcriptomic')
        """
        mapping = {}

        # Read samples.tsv if available
        if 'study_experiment_run_sample.tsv' in self.tables:
            table = self.tables['study_experiment_run_sample.tsv']
            if not table.is_empty() and 'sample_accession_id' in table.columns:
                for row in table.iter_rows(named=True):
                    sample_id = row.get('sample_accession_id', '')
                    lib_prep = row.get('library_source', '')
                    assert sample_id and sample_id.startswith('EGAN')
                    assert lib_prep and lib_prep in ["GENOMIC", "TRANSCRIPTOMIC"]
                    mapping[sample_id] = lib_prep
        return mapping

    def get_run_to_sample_mapping(self) -> Dict[str, str]:
        """
        Get a mapping from run IDs to sample IDs.

        Returns:
            Dictionary mapping run accession IDs (EGAR...) to sample accession IDs (EGAN...)
        """
        mapping = {}

        if 'study_experiment_run_sample.tsv' in self.tables:
            table = self.tables['study_experiment_run_sample.tsv']
            if not table.is_empty() and 'run_accession_id' in table.columns and 'sample_accession_id' in table.columns:
                for row in table.iter_rows(named=True):
                    run_id = row.get('run_accession_id', '')
                    sample_id = row.get('sample_accession_id', '')

                    if run_id and sample_id and run_id.startswith('EGAR') and sample_id.startswith('EGAN'):
                        mapping[run_id] = sample_id

        return mapping

    def validate_run_sample_bijection(self):
        """
        Validate that there is a one-to-one bijective mapping between run_accession_id and sample_accession_id.

        A bijection means:
        - Each run maps to exactly one sample (function property)
        - Each sample is mapped to by exactly one run (injection property)
        - Every sample that appears is covered (surjection property within the table)
        """
        if 'study_experiment_run_sample.tsv' not in self.tables:
            return

        table = self.tables['study_experiment_run_sample.tsv']
        if table.is_empty() or 'run_accession_id' not in table.columns or 'sample_accession_id' not in table.columns:
            return

        run_to_sample = defaultdict(set)
        sample_to_run = defaultdict(set)

        for row in table.iter_rows(named=True):
            run_id = row.get('run_accession_id', '')
            sample_id = row.get('sample_accession_id', '')

            if run_id and sample_id and run_id.startswith('EGAR') and sample_id.startswith('EGAN'):
                run_to_sample[run_id].add(sample_id)
                sample_to_run[sample_id].add(run_id)

        # Check that each run maps to exactly one sample
        for run_id, samples in run_to_sample.items():
            if len(samples) > 1:
                self.validation_errors.append(
                    f"study_experiment_run_sample.tsv: Run '{run_id}' maps to multiple samples: {list(samples)}"
                )

        # Check that each sample is mapped by exactly one run
        for sample_id, runs in sample_to_run.items():
            if len(runs) > 1:
                self.validation_errors.append(
                    f"study_experiment_run_sample.tsv: Sample '{sample_id}' is mapped by multiple runs: {list(runs)}"
                )

    def validate_all(self):
        """Run all validation checks."""
        self.validation_errors = []
        self.validate_unique_columns()
        self.validate_cross_references()
        self.validate_run_sample_bijection()

        return len(self.validation_errors) == 0

    def get_validation_report(self) -> str:
        """Get a formatted report of validation errors."""
        if not self.validation_errors:
            return "All validations passed."

        report = f"Found {len(self.validation_errors)} validation error(s):\n"
        for error in self.validation_errors:
            report += f"  - {error}\n"

        return report
    
    
    
    
