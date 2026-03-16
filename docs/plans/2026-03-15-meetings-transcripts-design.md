# Meetings & Transcripts Runners Design

**Date**: 2026-03-15
**Status**: Approved

## Summary

Add two new runner modules to lex-microsoft_teams for Microsoft Graph API online meetings and meeting transcripts.

## Runners::Meetings

Online meeting management via `/users/{userId}/onlineMeetings`.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `list_meetings` | `GET /users/{userId}/onlineMeetings` | List online meetings |
| `get_meeting` | `GET /users/{userId}/onlineMeetings/{meetingId}` | Get meeting details |
| `create_meeting` | `POST /users/{userId}/onlineMeetings` | Create meeting |
| `update_meeting` | `PATCH /users/{userId}/onlineMeetings/{meetingId}` | Update meeting |
| `delete_meeting` | `DELETE /users/{userId}/onlineMeetings/{meetingId}` | Delete meeting |
| `get_meeting_by_join_url` | `GET .../onlineMeetings?$filter=joinWebUrl eq '{url}'` | Lookup by join URL |
| `list_attendance_reports` | `GET .../attendanceReports` | List attendance reports |
| `get_attendance_report` | `GET .../attendanceReports/{reportId}` | Get report with attendees |

## Runners::Transcripts

Transcript access via `/users/{userId}/onlineMeetings/{meetingId}/transcripts`.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `list_transcripts` | `GET .../transcripts` | List available transcripts |
| `get_transcript` | `GET .../transcripts/{transcriptId}` | Get transcript metadata |
| `get_transcript_content` | `GET .../transcripts/{transcriptId}/content` | Get content (VTT or DOCX) |

`get_transcript_content` accepts `format: :vtt` (default) or `format: :docx`. Maps to `Accept` header. VTT returns plain text, DOCX returns binary.

## Wiring

- Both included in standalone `Client` class
- Both required in entry point `microsoft_teams.rb`
- New permissions: `OnlineMeetingTranscript.Read.All`, `OnlineMeeting.Read.All`

## Pattern

Same flat runner pattern as all existing modules: include `Helpers::Client`, use `graph_connection(**)`, return `{ result: response.body }`.

---

# Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Meetings and Transcripts runner modules to lex-microsoft_teams

**Architecture:** Two flat runner modules following the identical pattern as Channels/ChannelMessages. Each includes `Helpers::Client`, uses `graph_connection(**)`, returns `{ result: response.body }`. Both wired into the standalone `Client` class and the entry point.

**Tech Stack:** Ruby, Faraday, RSpec, Microsoft Graph API v1.0

---

### Task 1: Meetings runner - spec

**Files:**
- Create: `spec/legion/extensions/microsoft_teams/runners/meetings_spec.rb`

**Step 1: Write the spec file**

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Meetings do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_meetings' do
    it 'lists online meetings for a user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'm1', 'subject' => 'Standup' }] })
      allow(graph_conn).to receive(:get).with('/users/u1/onlineMeetings').and_return(response)

      result = runner.list_meetings(user_id: 'u1')
      expect(result[:result]['value'].first['subject']).to eq('Standup')
    end
  end

  describe '#get_meeting' do
    it 'retrieves a meeting by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1', 'subject' => 'Standup' })
      allow(graph_conn).to receive(:get).with('/users/u1/onlineMeetings/m1').and_return(response)

      result = runner.get_meeting(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['id']).to eq('m1')
    end
  end

  describe '#create_meeting' do
    it 'creates an online meeting' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm2', 'subject' => 'Review' })
      allow(graph_conn).to receive(:post)
        .with('/users/u1/onlineMeetings', hash_including(subject: 'Review'))
        .and_return(response)

      result = runner.create_meeting(user_id: 'u1', subject: 'Review',
                                     start_time: '2026-03-15T10:00:00Z',
                                     end_time: '2026-03-15T11:00:00Z')
      expect(result[:result]['subject']).to eq('Review')
    end
  end

  describe '#update_meeting' do
    it 'updates a meeting' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1', 'subject' => 'Updated' })
      allow(graph_conn).to receive(:patch)
        .with('/users/u1/onlineMeetings/m1', hash_including(subject: 'Updated'))
        .and_return(response)

      result = runner.update_meeting(user_id: 'u1', meeting_id: 'm1', subject: 'Updated')
      expect(result[:result]['subject']).to eq('Updated')
    end
  end

  describe '#delete_meeting' do
    it 'deletes a meeting' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete).with('/users/u1/onlineMeetings/m1').and_return(response)

      result = runner.delete_meeting(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]).to eq('')
    end
  end

  describe '#get_meeting_by_join_url' do
    it 'finds a meeting by join URL' do
      response = instance_double(Faraday::Response,
                                 body: { 'value' => [{ 'id' => 'm1', 'joinWebUrl' => 'https://teams.microsoft.com/l/meetup/123' }] })
      allow(graph_conn).to receive(:get)
        .with('/users/u1/onlineMeetings', hash_including('$filter'))
        .and_return(response)

      result = runner.get_meeting_by_join_url(user_id: 'u1', join_url: 'https://teams.microsoft.com/l/meetup/123')
      expect(result[:result]['value'].first['id']).to eq('m1')
    end
  end

  describe '#list_attendance_reports' do
    it 'lists attendance reports for a meeting' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'r1' }] })
      allow(graph_conn).to receive(:get).with('/users/u1/onlineMeetings/m1/attendanceReports').and_return(response)

      result = runner.list_attendance_reports(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['value']).not_to be_empty
    end
  end

  describe '#get_attendance_report' do
    it 'retrieves a specific attendance report' do
      response = instance_double(Faraday::Response,
                                 body: { 'id' => 'r1', 'attendanceRecords' => [{ 'identity' => { 'displayName' => 'Alice' } }] })
      allow(graph_conn).to receive(:get).with('/users/u1/onlineMeetings/m1/attendanceReports/r1').and_return(response)

      result = runner.get_attendance_report(user_id: 'u1', meeting_id: 'm1', report_id: 'r1')
      expect(result[:result]['attendanceRecords']).not_to be_empty
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/meetings_spec.rb`
Expected: FAIL — `uninitialized constant Legion::Extensions::MicrosoftTeams::Runners::Meetings`

---

### Task 2: Meetings runner - implementation

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/runners/meetings.rb`

**Step 1: Write the runner**

```ruby
# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Meetings
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_meetings(user_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings")
            { result: response.body }
          end

          def get_meeting(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def create_meeting(user_id:, subject:, start_time:, end_time:, **)
            payload = {
              subject: subject,
              startDateTime: start_time,
              endDateTime: end_time
            }
            response = graph_connection(**).post("/users/#{user_id}/onlineMeetings", payload)
            { result: response.body }
          end

          def update_meeting(user_id:, meeting_id:, subject: nil, start_time: nil, end_time: nil, **)
            payload = {}
            payload[:subject] = subject if subject
            payload[:startDateTime] = start_time if start_time
            payload[:endDateTime] = end_time if end_time
            response = graph_connection(**).patch("/users/#{user_id}/onlineMeetings/#{meeting_id}", payload)
            { result: response.body }
          end

          def delete_meeting(user_id:, meeting_id:, **)
            response = graph_connection(**).delete("/users/#{user_id}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def get_meeting_by_join_url(user_id:, join_url:, **)
            params = { '$filter' => "joinWebUrl eq '#{join_url}'" }
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings", params)
            { result: response.body }
          end

          def list_attendance_reports(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/attendanceReports")
            { result: response.body }
          end

          def get_attendance_report(user_id:, meeting_id:, report_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/attendanceReports/#{report_id}")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/meetings_spec.rb`
Expected: All 8 examples pass

**Step 3: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/runners/meetings.rb spec/legion/extensions/microsoft_teams/runners/meetings_spec.rb
git commit -m "add meetings runner with specs"
```

---

### Task 3: Transcripts runner - spec

**Files:**
- Create: `spec/legion/extensions/microsoft_teams/runners/transcripts_spec.rb`

**Step 1: Write the spec file**

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Transcripts do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_transcripts' do
    it 'lists transcripts for a meeting' do
      response = instance_double(Faraday::Response,
                                 body: { 'value' => [{ 'id' => 't1', 'createdDateTime' => '2026-03-15T12:00:00Z' }] })
      allow(graph_conn).to receive(:get)
        .with('/users/u1/onlineMeetings/m1/transcripts')
        .and_return(response)

      result = runner.list_transcripts(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['value'].first['id']).to eq('t1')
    end
  end

  describe '#get_transcript' do
    it 'retrieves transcript metadata' do
      response = instance_double(Faraday::Response, body: { 'id' => 't1', 'createdDateTime' => '2026-03-15T12:00:00Z' })
      allow(graph_conn).to receive(:get)
        .with('/users/u1/onlineMeetings/m1/transcripts/t1')
        .and_return(response)

      result = runner.get_transcript(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1')
      expect(result[:result]['id']).to eq('t1')
    end
  end

  describe '#get_transcript_content' do
    let(:vtt_body) { "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nHello everyone" }

    it 'retrieves transcript content as VTT by default' do
      response = instance_double(Faraday::Response, body: vtt_body)
      allow(graph_conn).to receive(:get) do |path, _params, &block|
        block&.call(Faraday::Request.new)
        response
      end

      result = runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1')
      expect(result[:result]).to include('WEBVTT')
    end

    it 'accepts format: :docx' do
      response = instance_double(Faraday::Response, body: 'binary-docx-content')
      allow(graph_conn).to receive(:get) do |path, _params, &block|
        block&.call(Faraday::Request.new)
        response
      end

      result = runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1', format: :docx)
      expect(result[:result]).to eq('binary-docx-content')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/transcripts_spec.rb`
Expected: FAIL — `uninitialized constant Legion::Extensions::MicrosoftTeams::Runners::Transcripts`

---

### Task 4: Transcripts runner - implementation

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/runners/transcripts.rb`

**Step 1: Write the runner**

```ruby
# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Transcripts
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          CONTENT_TYPES = {
            vtt:  'text/vtt',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          }.freeze

          def list_transcripts(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts")
            { result: response.body }
          end

          def get_transcript(user_id:, meeting_id:, transcript_id:, **)
            response = graph_connection(**).get(
              "/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}"
            )
            { result: response.body }
          end

          def get_transcript_content(user_id:, meeting_id:, transcript_id:, format: :vtt, **)
            accept = CONTENT_TYPES.fetch(format, CONTENT_TYPES[:vtt])
            response = graph_connection(**).get(
              "/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}/content"
            ) do |req|
              req.headers['Accept'] = accept
            end
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/transcripts_spec.rb`
Expected: All 4 examples pass

**Step 3: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/runners/transcripts.rb spec/legion/extensions/microsoft_teams/runners/transcripts_spec.rb
git commit -m "add transcripts runner with specs"
```

---

### Task 5: Wire into entry point and Client

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams.rb`
- Modify: `lib/legion/extensions/microsoft_teams/client.rb`

**Step 1: Add requires to entry point**

In `lib/legion/extensions/microsoft_teams.rb`, add after the `presence` require (line 14):
```ruby
require 'legion/extensions/microsoft_teams/runners/meetings'
require 'legion/extensions/microsoft_teams/runners/transcripts'
```

**Step 2: Add includes to Client**

In `lib/legion/extensions/microsoft_teams/client.rb`, add requires after `presence` require (line 13):
```ruby
require 'legion/extensions/microsoft_teams/runners/meetings'
require 'legion/extensions/microsoft_teams/runners/transcripts'
```

And add includes after `include Runners::Presence` (line 29):
```ruby
include Runners::Meetings
include Runners::Transcripts
```

**Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All specs pass (previous 132 + 12 new = 144)

**Step 4: Run linter**

Run: `bundle exec rubocop`
Expected: No offenses

**Step 5: Commit**

```bash
git add lib/legion/extensions/microsoft_teams.rb lib/legion/extensions/microsoft_teams/client.rb
git commit -m "wire meetings and transcripts runners into client and entry point"
```

---

### Task 6: Version bump, CHANGELOG, docs update

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/version.rb` — bump to `0.4.0`
- Modify: `CHANGELOG.md` — add entry
- Modify: `CLAUDE.md` — add Meetings and Transcripts to architecture and permissions table
- Modify: `README.md` — add Meetings and Transcripts if documented

**Step 1: Bump version to 0.4.0**

In `version.rb`, change `VERSION = '0.3.0'` to `VERSION = '0.4.0'`

**Step 2: Update CHANGELOG.md**

Add under `## [Unreleased]` (or create the file):
```markdown
## [0.4.0] - 2026-03-15

### Added
- Meetings runner: list, get, create, update, delete online meetings, lookup by join URL, attendance reports
- Transcripts runner: list, get metadata, get content (VTT/DOCX format support)
- New Graph API permissions: `OnlineMeeting.Read.All`, `OnlineMeetingTranscript.Read.All`
```

**Step 3: Update CLAUDE.md architecture diagram and permissions table**

Add `Meetings` and `Transcripts` to the Runners list. Add permissions to the table.

**Step 4: Run full suite one more time**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: All green

**Step 5: Commit**

```bash
git add -A
git commit -m "bump to 0.4.0, add changelog and docs for meetings/transcripts"
```
