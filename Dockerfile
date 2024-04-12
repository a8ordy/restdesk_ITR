FROM debian

WORKDIR /
RUN apt update -y && apt install -y g++ gcc git curl nasm yasm libgtk-3-dev clang libxcb-randr0-dev libxdo-dev libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev libpulse-dev cmake unzip zip sudo libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev cmake ninja-build && rm -rf /var/lib/apt/lists/*

RUN git clone --branch 2023.04.15 --depth=1 https://github.com/microsoft/vcpkg
RUN /vcpkg/bootstrap-vcpkg.sh -disableMetrics
RUN /vcpkg/vcpkg --disable-metrics install libvpx libyuv opus aom

RUN groupadd -r user && useradd -r -g user user --home /home/user && mkdir -p /home/user && chown user /home/user && echo "user  ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/user
WORKDIR /home/user
RUN curl -LO https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so
USER user
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup.sh
RUN chmod +x rustup.sh
RUN ./rustup.sh -y

USER root
ENV HOME=/home/user
COPY ./entrypoint /
ENTRYPOINT ["/entrypoint"]
