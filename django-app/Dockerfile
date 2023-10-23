FROM python:3.5

# create app dir
WORKDIR /app

# install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# bundle app source
COPY . .
# expose port
EXPOSE 8080

ENTRYPOINT ["python", "manage.py"]
CMD ["runserver", "0.0.0.0:8080"]