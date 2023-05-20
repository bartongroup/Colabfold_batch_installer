# Build with: docker buildx build --platform linux/amd64 -t jamescabbott/colabfold_batch:1.5.2 -o 'type=local,dest=colabfold_batch.1.5.2.tar' . 2>&1 |tee build.log

FROM condaforge/mambaforge

ENV CONDA_PREFIX=/opt/conda
COPY colabfold_batch.yaml .
COPY setup.sh .

RUN conda config --add channels conda-forge
RUN conda config --add channels bioconda

RUN ./setup.sh

RUN mamba clean -a -y

