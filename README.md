# Deploy an example Django app with Kubernetes (on Windows with Docker Desktop and WSL)

This setup has only been tested on Windows, but probably works on macOS and Linux too.

For the Django app README, refer to [README.md](django-app/README.md)

## 1. Instructions: Install prerequisites

### 1.1. Kind and Kubectl

1. Install `kind`: [https://kind.sigs.k8s.io/docs/user/quick-start](https://kind.sigs.k8s.io/docs/user/quick-start/)
2. Install `kubectl`: [https://kubernetes.io/docs/tasks/tools/install-kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

### 1.2. Docker Desktop

1. Docker Desktop _should_ have been installed as a dependency of `kind`, but in case it still isn't installed, follow the instructions at [https://docs.docker.com/desktop/install/windows-install](https://docs.docker.com/desktop/install/windows-install)
	- Prerequisite: Windows WSL
2. Start Docker Desktop

## 2. Instructions: Kubernetes Deployment

### Summary
- Build Django app Docker image and push to a local repository (which Kubernetes will pull the image from when creating containers)
- Create a Kubernetes cluster
- Deploy Django app containers to the cluster
- Make the app scalable
- Enable access (i.e. ingress) to the app from outside the cluster

### 2.1. Build Docker image

```
docker build ./django-app -t django-example-app
```

### 2.2. Create Kubernetes cluster

```
kind create cluster --config kind-config.yaml
```

### 2.3. Add Docker image to local registry

1. Create local Docker image registry: `./create_local_docker_registry.sh letchik-cluster`
	- Why: So that the Django app Docker image can be pushed to a local registry instead of Docker Hub
2. Tag Django app image for the local registry: `docker tag django-example-app:latest localhost:5001/django-example-app:latest`
3. Push Django app image to the local registry: `docker push localhost:5001/django-example-app:latest`

### 2.4. Deploy app to Kubernetes

1. Deploy Django app: `kubectl apply -f letchik-django-deployment.yaml`
2. Validate pod deployment: `kubectl get pods`
3. Validate service creation: `kubectl get services`
4. Validate that `DJANGO_FAKE_DB_USER` and `DJANGO_FAKE_DB_PASSWORD` are exposed as env variables: `kubectl exec -i -t <POD_NAME> -- sh -c 'env | grep DJANGO_FAKE'`

### 2.5. Enable Autoscaling

1. Add the Kubernetes [metrics-server](https://github.com/kubernetes-sigs/metrics-server): `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
	- Note: The autoscaler needs to fetch metrics from somewhere in order to compute e.g. CPU utilisation
2. Apply metrics-server patch: `kubectl patch deployment metrics-server -n kube-system --type 'json' -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'`
	- Note: The autoscaler won't be able to fetch metrics from the metrics server without this patch
3. Enable autoscaling: `kubectl apply -f letchik-django-autoscale.yaml`
4. Validate that autoscaling is turned on
	- `kubectl get horizontalpodautoscalers`
	- `kubectl describe hpa django-hpa`

### 2.6. Enable Ingress

1. Add the [Nginx Ingress controler](https://github.com/kubernetes/ingress-nginx): `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`
2. Enable Ingress using the Nginx controller: `kubectl apply -f letchik-django-nginx-ingress.yaml`
2. Validate that ingress is turned on: `kubectl get ingress --all-namespaces`

## 3. Kubernetes testing

Run outside of the cluster

```
curl http://127.0.0.1/api/?format=json

curl http://localhost/api/?format=json
```

Expected responses

```
{"articles":"http://127.0.0.1/api/articles?format=json"}

{"articles":"http://localhost/api/articles?format=json"}
```

Or open `http://127.0.0.1/api/` in the local machine's web browser

## 4. Tear down

Autoscaling: `kubectl delete -f letchik-django-autoscale.yaml`

Ingress: `kubectl delete -f letchik-django-nginx-ingress.yaml`

Deployment: `kubectl delete -f letchik-django-deployment.yaml`

Cluster: `kind delete cluster --name letchik-cluster`

## Notes

- The Django app uses a SQLite DB file, so configuring a persistent volume didn't really make sense.

