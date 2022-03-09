
scalaVersion in ThisBuild := "2.12.9"
name := "icoscp-sbt-tsgen"
organization := "se.lu.nateko.cp"
version := "0.1.1"

sbtPlugin := true

publishTo := {
	val nexus = "https://repo.icos-cp.eu/content/repositories/"
	if (isSnapshot.value)
		Some("snapshots" at nexus + "snapshots")
	else
		Some("releases"  at nexus + "releases")
}

credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")

libraryDependencies ++= Seq(
	"org.scalameta" %% "scalameta" % "4.2.3",
	"org.scalatest" %% "scalatest" % "3.0.8" % "test"
)
