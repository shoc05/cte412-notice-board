# Campus Notice Board - one Dockerfile, three release images.
# Build (see README.md):
#   docker build --build-arg APP_VERSION=1.0.0 --build-arg STUDENT_ID=02230146 \
#                -t notice-board:02230146-1.0.0 app/
#
# Alpine-based image (course rule: Alpine or busybox only).
FROM python:3.13-alpine

# Which release this image is: 1.0.0, 1.1.0 or 1.2.0-broken.
ARG APP_VERSION=1.0.0
# Student number, returned by GET /version.
ARG STUDENT_ID=02230146

ENV APP_VERSION=${APP_VERSION} \
    STUDENT_ID=${STUDENT_ID} \
    PYTHONUNBUFFERED=1

# Non-root user with a numeric UID so that Kubernetes can verify runAsNonRoot.
RUN addgroup -S app && adduser -S -D -H -u 10001 -G app app

WORKDIR /app
COPY app.py .

USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
