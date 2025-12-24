# Use Ubuntu 24.04 LTS as the base image
FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set the working directory in the container
WORKDIR /app

# Install system dependencies and Python
# We need to install python3, pip, venv, and build tools manually on Ubuntu
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    gcc \
    pciutils \
    iproute2 \
    lm-sensors \
    lshw \
    && rm -rf /var/lib/apt/lists/*

# Create a virtual environment to manage Python packages (PEP 668 compliance)
RUN python3 -m venv /opt/venv

# Activate the virtual environment by adding it to the PATH
# This ensures that 'python' and 'pip' commands point to the venv versions
ENV PATH="/opt/venv/bin:$PATH"

# Copy the current directory contents into the container at /app
COPY . /app

# Install any needed packages specified in requirements.txt (or explicitly here)
RUN pip install --no-cache-dir -r requirements.txt

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Run web_server.py when the container launches
CMD ["python", "web_server.py"]




