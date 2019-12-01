docker build -t biocdevel .
docker run -d -it -e PASSWORD=bioc -p 8788:8787 -v /home/felix/GitHub:/home/rstudio/github --name biocdevel biocdevel

