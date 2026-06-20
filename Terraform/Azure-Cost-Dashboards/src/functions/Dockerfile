FROM mcr.microsoft.com/azure-functions/python:4-python3.11 AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM mcr.microsoft.com/azure-functions/python:4-python3.11
ENV AzureWebJobsScriptRoot=/home/site/wwwroot
COPY --from=build /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY . /home/site/wwwroot
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://localhost/api/health || exit 1
USER app