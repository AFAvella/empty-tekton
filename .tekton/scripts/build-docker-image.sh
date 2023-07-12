# Input env variables (can be received via a pipeline environment properties.file.
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "DOCKER_ROOT=${DOCKER_ROOT}"
echo "DOCKER_FILE=${DOCKER_FILE}"
#Pedazo código nuevo

source /steps/next-step-env.properties
export $(cut -d= -f1 /steps/next-step-env.properties)

# Manage multiple tags for an image
# Add dynamically computed tags
printf "#!/bin/sh\n" > /steps/additionalTags.sh
printf "%s " '$(params.additional-tags-script)' >> /steps/additionalTags.sh
chmod +x /steps/additionalTags.sh

# Send stdout to the tags list; don't touch stderr.
/steps/additionalTags.sh > /steps/tags.lst

# Add image pipeline resource
if [ "${IMAGE_TAG}" ]; then
  echo "${IMAGE_TAG}" >> /steps/tags.lst
fi
# Add tags provided using task parameter
if [ "$(params.additional-tags)" ];  then
  echo "$(params.additional-tags)" | sed 's/,/\n/g' >> /steps/tags.lst
fi
echo "#######################"
echo "Image Tags:"
cat /steps/tags.lst
echo "#######################"
IMAGE_REPOSITORY="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
# Add the full image url with tags - use # as separator in case IMAGE_NAME contains /
sed -i "s#^#$IMAGE_REPOSITORY:#" /steps/tags.lst
sort -u -o /steps/tags.lst /steps/tags.lst
echo "Full Image URLs:"
cat /steps/tags.lst
echo "#######################"
BUILDKIT_IMAGE_NAMES=$(tr -s '\r\n' ',' < /steps/tags.lst | sed -e 's/,$/\n/')
if [ -z "$BUILDKIT_IMAGE_NAMES" ]; then
# Set default image name for buildkit to push
BUILDKIT_IMAGE_NAMES="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
fi
echo "Buildkit Image names: $BUILDKIT_IMAGE_NAMES"

BUILD_ARG_LIST='$(params.build-args)'
for buildArg in $BUILD_ARG_LIST; do
BUILD_ARGS="${BUILD_ARGS} --opt build-arg:$buildArg "
done

buildctl --addr tcp://0.0.0.0:1234 build \
--progress=plain \
--frontend=dockerfile.v0 \
--opt filename=$(params.dockerfile) \
${BUILD_ARGS} \
--local context=$(workspaces.source.path)/$(params.path-to-context) \
--local dockerfile=$(workspaces.source.path)/$(params.path-to-dockerfile) \
--exporter=image --exporter-opt "name=$BUILDKIT_IMAGE_NAMES" --exporter-opt "push=$(params.push-to-registry)" \
--export-cache type=inline \
--import-cache type=registry,ref=$IMAGE_REPOSITORY 2>&1 | tee /steps/build.log

# Using the deprecated --exporter option for now as the multiple name/tags using --output option
# is not working as expected: https://github.com/moby/buildkit/issues/797#issuecomment-581346240
# --output type=image,"name=$(params.image-url):1.0.0,$(params.image-url)",push=true

# it is not possible to specify multiple exporters for now
# --output type=oci,dest=/builder/home/image-outputs/built-image/output.tar \
# It is possible to assign multiple tags to the image with latest version of buildkit-image
# see https://github.com/moby/buildkit/issues/797
