defmodule AcexGateway.EventsStoreTest do
  use ExUnit.Case, async: false

  alias AcexGateway.Events.Store, as: EventsStore

  @test_file "tmp/test_events.json"

  setup do
    File.rm(@test_file)
    EventsStore.clear_events()

    on_exit(fn ->
      File.rm(@test_file)
      EventsStore.clear_events()
    end)

    :ok
  end

  describe "events storage and ETS operations" do
    test "sets and lists events" do
      sample_events = [
        %{
          "name" => "19:00 - Real Madrid vs Barcelona",
          "logo" => "https://i.ibb.co/2vhFM7h/soccer-ball-variant.png",
          "sources" => [
            "1111111111111111111111111111111111111111",
            "2222222222222222222222222222222222222222"
          ]
        },
        %{
          "name" => "14:00 - Djokovic vs Alcaraz",
          "logo" => "https://i.ibb.co/Yjyrpmh/ball.png",
          "sources" => [
            "3333333333333333333333333333333333333333"
          ]
        }
      ]

      {:ok, count} = EventsStore.set_events(sample_events)
      assert count == 2

      events = EventsStore.list_events()
      assert length(events) == 2

      football = Enum.find(events, &(&1["name"] == "19:00 - Real Madrid vs Barcelona"))
      assert football != nil
      assert football["group"] == "Live Football"
      assert length(football["sources"]) == 2

      tennis = Enum.find(events, &(&1["name"] == "14:00 - Djokovic vs Alcaraz"))
      assert tennis != nil
      assert tennis["group"] == "Live Tennis"
    end

    test "gets event by ID and finds by source hash" do
      sample = [
        %{
          "id" => "event-final",
          "name" => "Grand Final",
          "sources" => ["abcdef1234567890abcdef1234567890abcdef12"]
        }
      ]

      {:ok, 1} = EventsStore.set_events(sample)

      assert EventsStore.get_event("event-final")["name"] == "Grand Final"
      assert EventsStore.find_event_by_source("abcdef1234567890abcdef1234567890abcdef12")["id"] == "event-final"
      assert EventsStore.get_event("non-existent") == nil
    end

    test "promotes working source to front" do
      sample = [
        %{
          "id" => "match-1",
          "name" => "Match 1",
          "sources" => [
            "1111111111111111111111111111111111111111",
            "2222222222222222222222222222222222222222"
          ]
        }
      ]

      {:ok, 1} = EventsStore.set_events(sample)
      :ok = EventsStore.promote_event_source("match-1", "2222222222222222222222222222222222222222")

      event = EventsStore.get_event("match-1")
      assert hd(event["sources"]) == "2222222222222222222222222222222222222222"
    end

    test "prunes dead source from event" do
      sample = [
        %{
          "id" => "match-2",
          "name" => "Match 2",
          "sources" => [
            "1111111111111111111111111111111111111111",
            "2222222222222222222222222222222222222222"
          ]
        }
      ]

      {:ok, 1} = EventsStore.set_events(sample)
      EventsStore.prune_dead_source("match-2", "1111111111111111111111111111111111111111")

      event = EventsStore.get_event("match-2")
      assert event["sources"] == ["2222222222222222222222222222222222222222"]
    end

    test "exports M3U playlist correctly" do
      sample = [
        %{
          "id" => "champions-league",
          "name" => "20:00 Final",
          "group" => "Live Football",
          "logo" => "https://example.com/logo.png",
          "sources" => ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        }
      ]

      {:ok, 1} = EventsStore.set_events(sample)
      m3u = EventsStore.export_m3u("http://localhost:8686", %{"format" => "hls"})

      assert String.contains?(m3u, "#EXTM3U")
      assert String.contains?(m3u, "#EXTINF:-1 tvg-id=\"champions-league\"")
      assert String.contains?(m3u, "group-title=\"Live Football\"")
      assert String.contains?(m3u, "http://localhost:8686/h/champions-league.m3u8")
    end
  end
end
