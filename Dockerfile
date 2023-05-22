# Test build with: docker buildx build --platform linux/amd64 -t colabfold_batch:1.5.2 --load .

FROM condaforge/mambaforge

ENV CONDA_PREFIX=/opt/conda
COPY colabfold_batch.yaml .
COPY setup.sh .

RUN ./setup.sh && \
	rm colabfold_batch.yaml setup.sh
