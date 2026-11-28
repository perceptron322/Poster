package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"slices"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/event"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readconcern"
	"go.mongodb.org/mongo-driver/mongo/readpref"
	"go.mongodb.org/mongo-driver/tag"
	"go.mongodb.org/mongo-driver/x/mongo/driver/topology"
)

type readCheck struct {
	name       string
	preference *readpref.ReadPref
	hosts      []string
}

func main() {
	primary := flag.String("primary", "", "Адрес ожидаемого Primary")
	missingTag := flag.Bool("missing-tag", false, "Проверить чтение с тегом недоступного Secondary")
	flag.Parse()

	var primaries []string
	if *primary != "" {
		primaries = []string{*primary}
	}
	secondaries := flag.Args()
	primaryPreferred := primaries
	if len(primaries) == 0 {
		primaryPreferred = secondaries
	}
	secondaryPreferred := secondaries
	if len(secondaries) == 0 {
		secondaryPreferred = primaries
	}
	checks := []readCheck{
		{"primary", readpref.Primary(), primaries},
		{"primaryPreferred", readpref.PrimaryPreferred(), primaryPreferred},
		{"secondary", readpref.Secondary(), secondaries},
		{"secondaryPreferred", readpref.SecondaryPreferred(), secondaryPreferred},
		{"nearest", readpref.Nearest(), append(slices.Clone(primaries), secondaries...)},
	}
	if *missingTag {
		tagged := readpref.WithTagSets(tag.Set{{Name: "node", Value: "txfault2"}})
		checks = append(checks,
			readCheck{"secondary (node:txfault2)", readpref.Secondary(tagged), nil},
			readCheck{"secondaryPreferred (node:txfault2)", readpref.SecondaryPreferred(tagged), primaries},
		)
	}
	if err := runChecks(os.Getenv("MONGO_URI"), checks, len(primaries) > 0, len(secondaries) > 0); err != nil {
		log.Fatal(err)
	}
}

func runChecks(uri string, checks []readCheck, hasPrimary, hasSecondary bool) error {
	var host string
	monitor := &event.CommandMonitor{
		Succeeded: func(_ context.Context, evt *event.CommandSucceededEvent) {
			if evt.CommandName == "find" {
				// ConnectionID содержит адрес узла и идентификатор соединения.
				host, _, _ = strings.Cut(evt.ConnectionID, "[")
			}
		},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri).
		SetReadConcern(readconcern.Majority()).
		SetServerSelectionTimeout(3*time.Second).
		SetMonitor(monitor))
	if err != nil {
		return err
	}
	defer client.Disconnect(ctx)

	// Дожидаемся обнаружения доступных ролей до проверки режимов Preferred.
	if hasPrimary {
		if err := client.Ping(ctx, readpref.Primary()); err != nil {
			return fmt.Errorf("проверка доступности Primary: %w", err)
		}
	}
	if hasSecondary {
		if err := client.Ping(ctx, readpref.Secondary()); err != nil {
			return fmt.Errorf("проверка доступности Secondary: %w", err)
		}
	}

	db := client.Database("poster_read_preference_demo")
	for _, check := range checks {
		var page struct {
			Rating struct {
				Count int     `bson:"count"`
				Avg   float64 `bson:"avg"`
			} `bson:"rating"`
		}
		host = ""
		pages := db.Collection("event_pages", options.Collection().SetReadPreference(check.preference))
		err := pages.FindOne(ctx, bson.M{"_id": 1}).Decode(&page)
		if err != nil {
			if len(check.hosts) != 0 || !errors.Is(err, topology.ErrServerSelectionTimeout) {
				return fmt.Errorf("%s: %w", check.name, err)
			}
			fmt.Printf("  %s -> тайм-аут выбора сервера\n", check.name)
			continue
		}
		if !slices.Contains(check.hosts, host) {
			return fmt.Errorf("%s: ответ получен с %q, ожидались узлы %v", check.name, host, check.hosts)
		}
		if page.Rating.Count != 2 || page.Rating.Avg != 4 {
			return fmt.Errorf("%s: неожиданный рейтинг мероприятия: %+v", check.name, page.Rating)
		}
		fmt.Printf("  %s -> %s (rating.count=%d, rating.avg=%g)\n", check.name, host, page.Rating.Count, page.Rating.Avg)
	}
	return nil
}
