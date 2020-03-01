# Docker-based Dev Environment

This contains a configuration—in `docker-compose.yml`—to run both the services you need to do development
(Postgres, Redis), but also a container in which to do your Rails development.

If you use this mechanism, you should run all commands inside the Docker container and only use your computer
(called the "host") for editing files.

## Commands

* `bin/build` will build a Docker image based on `Dockerfile`.  This will set up what you need for Rails
development of the app in `..`
* `bin/start` this will basically do `docker-compose up` and start up Postgres, Redis, and your dev box.
* `bin/exec` This will execute a command in your running container.  You can do something like `bin/exec bash` to
"log in" to the box.

## How it works

Docker Compose creates a private network, so your Rails app running in the container can see the Postgres database
via the hostname `db`, and can see Redis via the hostname `redis`.  You can add more stuff to `docker-compose.yml`
if you need to.

When you run your Rails app (which you can do via `bin/exec bin/run` or by doing `bin/exec bash` and then
`bin/run`), it will run on port 3000 of the Docker container.  This gets mapped to port 9000 of your computer.

