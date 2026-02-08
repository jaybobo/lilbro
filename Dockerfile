FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without development && bundle install

COPY . .

RUN chmod +x /app/entrypoint.rb

ENTRYPOINT ["/app/entrypoint.rb"]
