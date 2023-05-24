FROM condaforge/mambaforge

ENV CONDA_PREFIX=/opt/conda
ENV PATH /opt/conda/envs/colabfold_batch/bin:$PATH

COPY ../colabfold_batch.yaml .
COPY ../setup.sh .

RUN ./setup.sh && \
	rm colabfold_batch.yaml setup.sh && \
	/bin/bash -c "source activate colabfold_batch"

CMD ["colabfold_batch"]

