FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV VENV_PATH="/env"
ENV PATH="${VENV_PATH}/bin:${PATH}"
RUN apt update && \
    apt install --no-install-recommends --yes wget unzip python3 python3-venv python3-dev python3-pip python-is-python3
RUN python -m venv $VENV_PATH && \
    . ${VENV_PATH}/bin/activate && \
    pip install -U pip wheel setuptools --no-cache-dir

ENV CELLBENDER_RELEASE="0.3.0"
# Patch required to support torch>2.0.0, otherwise checkpoint.py will break
# see https://github.com/broadinstitute/CellBender/issues/296
RUN wget https://github.com/broadinstitute/CellBender/archive/refs/tags/v${CELLBENDER_RELEASE}.zip && \
    unzip "v${CELLBENDER_RELEASE}.zip" -d /opt && \
    rm -rf "v${CELLBENDER_RELEASE}.zip" && \
    cd /opt/CellBender-${CELLBENDER_RELEASE} && \
    sed "s/torch.save(model_obj, filebase + '_model.torch')/torch.save(model_obj.state_dict(), filebase + '_model.torch')/g" -i cellbender/remove_background/checkpoint.py && \
    sed "s/torch.save(scheduler, filebase + '_optim.torch')/scheduler.save(filebase + '_optim.torch')/g" -i cellbender/remove_background/checkpoint.py && \
    . ${VENV_PATH}/bin/activate && \
    pip install --editable .

# Fix html report generation
# https://github.com/broadinstitute/CellBender/issues/337
RUN . ${VENV_PATH}/bin/activate && \
    pip install -U lxml_html_clean

COPY Dockerfile /docker/
