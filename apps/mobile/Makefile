.PHONY: help test test-unit test-integration test-coverage test-watch clean build-dev build-staging build-prod analyze format

# Default target: show help
help:
	@echo "HavenKeep Mobile - Makefile Commands"
	@echo ""
	@echo "Testing:"
	@echo "  make test              Run all tests"
	@echo "  make test-unit         Run unit tests only"
	@echo "  make test-integration  Run integration tests"
	@echo "  make test-coverage     Generate test coverage report"
	@echo "  make test-watch        Run tests in watch mode"
	@echo ""
	@echo "Code Quality:"
	@echo "  make analyze           Run Dart analyzer"
	@echo "  make format            Format all Dart files"
	@echo "  make lint              Run linter"
	@echo ""
	@echo "Build:"
	@echo "  make build-dev         Build development APK"
	@echo "  make build-staging     Build staging APK"
	@echo "  make build-prod        Build production APK"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean             Clean build artifacts"
	@echo "  make get               Get dependencies"
	@echo "  make generate          Run code generation"

# Testing targets
test:
	flutter test

test-unit:
	flutter test --exclude-tags=integration

test-integration:
	flutter test integration_test/

test-coverage:
	@echo "Generating coverage report..."
	flutter test --coverage
	@if command -v genhtml >/dev/null 2>&1; then \
		genhtml coverage/lcov.info -o coverage/html; \
		echo "Coverage report generated at coverage/html/index.html"; \
	else \
		echo "Install lcov to generate HTML report: brew install lcov"; \
	fi

test-watch:
	flutter test --watch

# Code quality targets
analyze:
	flutter analyze

format:
	dart format lib/ test/

lint:
	flutter analyze

# Build targets
build-dev:
	flutter build apk --flavor development --dart-define=FLAVOR=development

build-staging:
	flutter build apk --flavor staging --dart-define=FLAVOR=staging

build-prod:
	flutter build apk --flavor production --dart-define=FLAVOR=production

# Utility targets
clean:
	flutter clean
	rm -rf coverage/

get:
	flutter pub get

generate:
	dart run build_runner build --delete-conflicting-outputs
