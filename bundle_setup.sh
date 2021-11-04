#!/bin/bash
#
# setup bundle to cache needed gems locally

bundle config set --local path .bundle/gems
bundle binstubs --all --path .bundle/.bin
bundle install
