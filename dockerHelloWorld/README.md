# Usage

In order to use this bundle, you will need to use a specific branch of Bindle to provision your vm. [link](https://github.com/CloudBindle/Bindle/compare/feature;docker_prototype)
When using this branch on Amazon, you will need a base image with a 3.8 kernel such as ubuntu 13.10. (This corresponds to the following in your json config)

    "AWS_IMAGE": "ami-1f7e4f76"

You will also need to install docker in order to successfully build a docker image from the source code (the image will be packaged into your bundle).
Follow [this](for Ubuntu).

Note, when running on Amazon, the build step for the docker image outputs a bunch of blank space and takes a while.
