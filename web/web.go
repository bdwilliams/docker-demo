package main

import (
	"net"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

func main() {
	router := gin.Default()
	gin.SetMode(gin.ReleaseMode)

	router.GET("/", func(c *gin.Context) {
		a := []string{}
		host, _ := os.Hostname()
		addrs, _ := net.LookupIP(host)
		for _, addr := range addrs {
			if ipv4 := addr.To4(); ipv4 != nil {
				a = append(a, ipv4.String())
			}
		}

		c.String(http.StatusOK, strings.Join(a[:], ", "))
	})

	router.Run(":8080")
}
