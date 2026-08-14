# Base runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj", "src/CustomerManagementSpike.Web/"]
RUN dotnet restore "src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj"
COPY . .
WORKDIR "/src/src/CustomerManagementSpike.Web"
RUN dotnet build "CustomerManagementSpike.Web.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Publish stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "CustomerManagementSpike.Web.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Final runtime stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "CustomerManagementSpike.Web.dll"]
