package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"

	rethinkdb "github.com/dancannon/gorethink"
)

var (
	session *rethinkdb.Session
)

func rootCall(w http.ResponseWriter, r *http.Request) {
	err := rethinkdb.Table("http_count").Update(map[string]interface{}{
		"views": rethinkdb.Row.Field("views").Add(1).Default(0),
	}).Exec(session)
	if err != nil {
		fmt.Println("Error 0: " + err.Error())
	}

	a := []string{}
	host, _ := os.Hostname()
	addrs, _ := net.LookupIP(host)
	for _, addr := range addrs {
		if ipv4 := addr.To4(); ipv4 != nil {
			a = append(a, ipv4.String())
		}
	}

	res, err := rethinkdb.Table("http_count").Run(session)
	if err != nil {
		fmt.Println("Error 1: " + err.Error())
	}
	defer res.Close()

	var rows map[string]interface{}
	err = res.One(&rows)
	var views string
	if err != nil {
		fmt.Println("Error 2: " + err.Error())
		views = "0"
	} else {
		views = strconv.Itoa(int(rows["views"].(float64)))
	}

	s := []string{"IP Address: " + strings.Join(a[:], ", "), "\nTotal Views: " + views}
	fmt.Println(s)
	io.WriteString(w, "Total Views: "+views+"\n")
}

func main() {
	fmt.Println("Running rethinkdb-simple-app...")

	var address string
	if os.Getenv("RETHINKDB_HOST") != "" {
		address = os.Getenv("RETHINKDB_HOST")
	} else {
		address = "dbmaster"
	}

	var err error
	session, err = rethinkdb.Connect(rethinkdb.ConnectOpts{
		Address:  address + ":28015",
		Database: "test",
		MaxIdle:  10,
		MaxOpen:  10,
	})

	if err != nil {
		fmt.Println("Error 3: " + err.Error())
	} else {
		fmt.Println("Successfully connected to " + address)
	}

	rethinkdb.TableCreate("http_count").Exec(session)
	res, err := rethinkdb.Table("http_count").Count().Run(session)
	if err != nil {
		fmt.Println("[WARN] COUNT: " + err.Error())
	}
	defer res.Close()

	var exists int
	_ = res.One(&exists)

	if exists == 0 {
		_, err := rethinkdb.Table("http_count").Insert(map[string]interface{}{
			"views": 0,
		}).RunWrite(session)
		if err != nil {
			fmt.Println("[WARN] Insert Error: " + err.Error())
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", rootCall)
	http.ListenAndServe(":8000", mux)
}
