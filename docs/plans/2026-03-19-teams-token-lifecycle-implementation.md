# Teams Token Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automatic delegated token validation on boot, periodic refresh, and browser re-auth for previously authenticated users.

**Architecture:** Two new actors (AuthValidator/Once, TokenRefresher/Every) plus two new methods on TokenCache. AuthValidator loads tokens on startup and recovers expired sessions. TokenRefresher keeps tokens fresh on a configurable 15-minute interval. Both trigger BrowserAuth for re-auth when a previously authenticated user's token cannot be refreshed.

**Tech Stack:** Ruby, RSpec, lex-microsoft_teams actor/helper conventions

---

### Task 1: Add `authenticated?` and `previously_authenticated?` to TokenCache

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/helpers/token_cache.rb:38-63`
- Test: `spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb`

**Step 1: Write the failing tests**

Add to the end of `token_cache_spec.rb`, before the final `end`:

```ruby
describe '#authenticated?' do
  it 'returns false when no delegated token is cached' do
    expect(cache.authenticated?).to be false
  end

  it 'returns true when a delegated token is stored' do
    cache.store_delegated_token(
      access_token: 'tok', refresh_token: 'ref',
      expires_in: 3600, scopes: 'scope1'
    )
    expect(cache.authenticated?).to be true
  end

  it 'returns false after clearing delegated token' do
    cache.store_delegated_token(
      access_token: 'tok', refresh_token: 'ref',
      expires_in: 3600, scopes: 'scope1'
    )
    cache.clear_delegated_token!
    expect(cache.authenticated?).to be false
  end
end

describe '#previously_authenticated?' do
  it 'returns false when no local file exists' do
    expect(cache.previously_authenticated?).to be false
  end

  it 'returns true after save_to_local' do
    cache.store_delegated_token(
      access_token: 'tok', refresh_token: 'ref',
      expires_in: 3600, scopes: 'scope1'
    )
    cache.save_to_local
    expect(cache.previously_authenticated?).to be true
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'authenticated?'`

**Step 3: Write minimal implementation**

Add these two methods to `token_cache.rb` after `clear_delegated_token!` (around line 63), before the `load_from_vault` method:

```ruby
def authenticated?
  @mutex.synchronize { !@delegated_cache.nil? }
end

def previously_authenticated?
  File.exist?(local_token_path)
end
```

**Step 4: Run tests to verify they pass**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb -v`
Expected: All pass (including existing specs)

**Step 5: Run rubocop**

Run: `cd extensions/lex-microsoft_teams && bundle exec rubocop lib/legion/extensions/microsoft_teams/helpers/token_cache.rb`
Expected: No offenses

**Step 6: Commit**

```bash
cd extensions/lex-microsoft_teams
git add lib/legion/extensions/microsoft_teams/helpers/token_cache.rb spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb
git commit -m "add authenticated? and previously_authenticated? to TokenCache"
```

---

### Task 2: Create AuthValidator actor

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/actors/auth_validator.rb`
- Test: `spec/legion/extensions/microsoft_teams/actors/auth_validator_spec.rb`

**Step 1: Write the spec file**

Create `spec/legion/extensions/microsoft_teams/actors/auth_validator_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Actors::Once)
  module Legion
    module Extensions
      module Actors
        class Once; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/once' unless $LOADED_FEATURES.include?('legion/extensions/actors/once')

require 'legion/extensions/microsoft_teams/actors/auth_validator'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::AuthValidator do
  subject(:actor) { described_class.allocate }

  let(:token_cache) { instance_double(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache) }
  let(:browser_auth) { instance_double(Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth) }

  before do
    allow(actor).to receive(:token_cache).and_return(token_cache)
  end

  it 'has a 2 second delay' do
    expect(actor.delay).to eq(2.0)
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end

  describe '#manual' do
    before do
      allow(token_cache).to receive(:previously_authenticated?).and_return(false)
    end

    context 'when token loads and refreshes successfully' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return('valid-token')
      end

      it 'logs success and does not trigger browser auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when token loads but refresh fails and previously authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when token loads but refresh fails and never authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
      end

      it 'does not trigger browser re-auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when no token file exists' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(false)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
      end

      it 'does nothing silently' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when no token loads but previously authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(false)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/actors/auth_validator_spec.rb -v`
Expected: FAIL — `LoadError: cannot load such file -- legion/extensions/microsoft_teams/actors/auth_validator`

**Step 3: Write the actor**

Create `lib/legion/extensions/microsoft_teams/actors/auth_validator.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class AuthValidator < Legion::Extensions::Actors::Once
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def delay
            2.0
          end

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError
            false
          end

          def token_cache
            @token_cache ||= Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
          end

          def manual
            loaded = token_cache.load_from_vault

            if loaded
              token = token_cache.cached_delegated_token
              if token
                log_info('Teams delegated auth restored')
              elsif token_cache.previously_authenticated?
                attempt_browser_reauth(token_cache)
              end
            elsif token_cache.previously_authenticated?
              log_warn('Token file found but could not load, attempting re-authentication')
              attempt_browser_reauth(token_cache)
            else
              log_debug('No Teams delegated auth configured, skipping')
            end
          rescue StandardError => e
            log_error("AuthValidator: #{e.message}")
          end

          private

          def attempt_browser_reauth(tc)
            settings = teams_auth_settings
            return false unless settings[:tenant_id] && settings[:client_id]

            log_warn('Delegated token expired, opening browser for re-authentication...')

            scopes = settings.dig(:delegated, :scopes) ||
                     Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth::DEFAULT_SCOPES
            browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
              tenant_id: settings[:tenant_id],
              client_id: settings[:client_id],
              scopes:    scopes
            )

            result = browser_auth.authenticate
            return false if result[:error]

            body = result[:result]
            tc.store_delegated_token(
              access_token:  body['access_token'],
              refresh_token: body['refresh_token'],
              expires_in:    body['expires_in'],
              scopes:        scopes
            )
            tc.save_to_vault
            log_info('Teams delegated auth restored via browser')
            true
          rescue StandardError => e
            log_error("Browser re-auth failed: #{e.message}")
            false
          end

          def teams_auth_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :auth) || {}
          end

          def log_info(msg)
            Legion::Logging.info(msg) if defined?(Legion::Logging)
          end

          def log_warn(msg)
            Legion::Logging.warn(msg) if defined?(Legion::Logging)
          end

          def log_debug(msg)
            Legion::Logging.debug(msg) if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/actors/auth_validator_spec.rb -v`
Expected: All pass

**Step 5: Run rubocop**

Run: `cd extensions/lex-microsoft_teams && bundle exec rubocop lib/legion/extensions/microsoft_teams/actors/auth_validator.rb`
Expected: No offenses

**Step 6: Commit**

```bash
cd extensions/lex-microsoft_teams
git add lib/legion/extensions/microsoft_teams/actors/auth_validator.rb spec/legion/extensions/microsoft_teams/actors/auth_validator_spec.rb
git commit -m "add AuthValidator actor for boot-time token validation"
```

---

### Task 3: Create TokenRefresher actor

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/actors/token_refresher.rb`
- Test: `spec/legion/extensions/microsoft_teams/actors/token_refresher_spec.rb`

**Step 1: Write the spec file**

Create `spec/legion/extensions/microsoft_teams/actors/token_refresher_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/every' unless $LOADED_FEATURES.include?('legion/extensions/actors/every')

require 'legion/extensions/microsoft_teams/actors/token_refresher'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::TokenRefresher do
  subject(:actor) { described_class.allocate }

  let(:token_cache) { instance_double(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache) }

  before do
    allow(actor).to receive(:token_cache).and_return(token_cache)
  end

  it 'has a default 900 second interval' do
    expect(actor.time).to eq(900)
  end

  it 'does not run immediately on start' do
    expect(actor.run_now?).to be false
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end

  describe '#manual' do
    context 'when not authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(false)
      end

      it 'skips refresh entirely' do
        expect(token_cache).not_to receive(:cached_delegated_token)
        actor.manual
      end
    end

    context 'when authenticated and refresh succeeds' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return('refreshed-token')
        allow(token_cache).to receive(:save_to_vault)
      end

      it 'saves the refreshed token' do
        actor.manual
        expect(token_cache).to have_received(:save_to_vault)
      end
    end

    context 'when authenticated but refresh fails and previously authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when authenticated but refresh fails and never previously authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
      end

      it 'does not trigger browser re-auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/actors/token_refresher_spec.rb -v`
Expected: FAIL — `LoadError: cannot load such file`

**Step 3: Write the actor**

Create `lib/legion/extensions/microsoft_teams/actors/token_refresher.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class TokenRefresher < Legion::Extensions::Actors::Every
          DEFAULT_REFRESH_INTERVAL = 900 # 15 minutes

          def runner_class    = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache
          def runner_function = 'cached_delegated_token'
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def time
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_REFRESH_INTERVAL unless delegated.is_a?(Hash)

            delegated[:refresh_interval] || DEFAULT_REFRESH_INTERVAL
          end

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError
            false
          end

          def token_cache
            @token_cache ||= Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
          end

          def manual
            return unless token_cache.authenticated?

            token = token_cache.cached_delegated_token
            if token
              token_cache.save_to_vault
            elsif token_cache.previously_authenticated?
              attempt_browser_reauth(token_cache)
            end
          rescue StandardError => e
            log_error("TokenRefresher: #{e.message}")
          end

          private

          def attempt_browser_reauth(tc)
            settings = teams_auth_settings
            return false unless settings[:tenant_id] && settings[:client_id]

            log_warn('Delegated token expired, opening browser for re-authentication...')

            scopes = settings.dig(:delegated, :scopes) ||
                     Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth::DEFAULT_SCOPES
            browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
              tenant_id: settings[:tenant_id],
              client_id: settings[:client_id],
              scopes:    scopes
            )

            result = browser_auth.authenticate
            return false if result[:error]

            body = result[:result]
            tc.store_delegated_token(
              access_token:  body['access_token'],
              refresh_token: body['refresh_token'],
              expires_in:    body['expires_in'],
              scopes:        scopes
            )
            tc.save_to_vault
            log_info('Teams delegated auth restored via browser')
            true
          rescue StandardError => e
            log_error("Browser re-auth failed: #{e.message}")
            false
          end

          def teams_auth_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :auth) || {}
          end

          def log_info(msg)
            Legion::Logging.info(msg) if defined?(Legion::Logging)
          end

          def log_warn(msg)
            Legion::Logging.warn(msg) if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec spec/legion/extensions/microsoft_teams/actors/token_refresher_spec.rb -v`
Expected: All pass

**Step 5: Run rubocop**

Run: `cd extensions/lex-microsoft_teams && bundle exec rubocop lib/legion/extensions/microsoft_teams/actors/token_refresher.rb`
Expected: No offenses

**Step 6: Commit**

```bash
cd extensions/lex-microsoft_teams
git add lib/legion/extensions/microsoft_teams/actors/token_refresher.rb spec/legion/extensions/microsoft_teams/actors/token_refresher_spec.rb
git commit -m "add TokenRefresher actor for periodic delegated token refresh"
```

---

### Task 4: Wire actors into entry point and run full suite

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams.rb`

**Step 1: Add requires to the entry point**

In `lib/legion/extensions/microsoft_teams.rb`, the actor files are auto-discovered by the framework (loaded via `Legion::Extensions::Core`). However, to ensure they are available, verify the actors directory is loaded. No explicit require needed — actors are discovered by convention. But if other actors in this extension are explicitly required elsewhere, check that pattern.

Actually, reviewing the codebase: actors are NOT explicitly required in the entry point. They are auto-discovered by the framework via the `Actor` module namespace. The existing actors (CacheBulkIngest, CacheSync, DirectChatPoller, ObservedChatPoller, MessageProcessor) are all loaded this way. No change to `microsoft_teams.rb` is needed.

**Step 2: Run full spec suite**

Run: `cd extensions/lex-microsoft_teams && bundle exec rspec -v`
Expected: All specs pass (should be ~200+ now)

**Step 3: Run rubocop on entire repo**

Run: `cd extensions/lex-microsoft_teams && bundle exec rubocop`
Expected: No offenses

**Step 4: Verify spec count increased**

Expected: 188 (previous) + 5 (TokenCache) + 9 (AuthValidator) + 8 (TokenRefresher) = ~210 specs

**Step 5: Commit integration verification**

No files changed in this step — this is verification only.

---

### Task 5: Bump version and update changelog

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/version.rb`
- Modify: `CHANGELOG.md`

**Step 1: Bump version**

Change version from `0.5.3` to `0.5.4` in `version.rb`.

**Step 2: Update changelog**

Add entry at top of CHANGELOG.md:

```markdown
## [0.5.4] - 2026-03-19

### Added
- `TokenCache#authenticated?` predicate for runtime delegated token state
- `TokenCache#previously_authenticated?` predicate for persistent auth history
- `AuthValidator` actor (Once): validates and restores delegated tokens on boot
- `TokenRefresher` actor (Every, 15min configurable): keeps delegated tokens fresh
- Automatic browser re-auth when previously authenticated user's token expires
- `refresh_interval` config key at `settings[:microsoft_teams][:auth][:delegated]`
```

**Step 3: Commit**

```bash
cd extensions/lex-microsoft_teams
git add lib/legion/extensions/microsoft_teams/version.rb CHANGELOG.md
git commit -m "bump version to 0.5.4, update changelog"
```

---

### Task 6: Push

**Step 1: Push to remote**

```bash
cd extensions/lex-microsoft_teams && git push
```
