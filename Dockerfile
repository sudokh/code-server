FROM centos:centos7
RUN yum update -y && \
    yum install -y epel-release && \
    yum upgrade -y upgrade -y && \
    yum install -y \
    wget \
    make \
    zsh \
    tmux \
    nvim \
    openssh-server

RUN sed -ri 's/^#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN echo 'root:password' | chpasswd
RUN ssh-keygen -t rsa -N "" -f /etc/ssh/ssh_host_rsa_key
EXPOSE 22

RUN touch ~/.vimrc && echo "set encoding=utf-8" > ~/.vimrc

CMD ["/usr/sbin/sshd", "-D"]