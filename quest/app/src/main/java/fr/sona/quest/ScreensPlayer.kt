package fr.sona.quest

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

private enum class Pane(val label: String) { Lyrics("Paroles"), Queue("À suivre") }

@Composable
fun PlayerScreen() {
    val look = LocalLook.current
    val queue by Hub.queue.collectAsState()
    val index by Hub.index.collectAsState()
    val queueName by Hub.queueName.collectAsState()
    val coverColor by Hub.coverColor.collectAsState()
    val sleepEnd by Hub.sleepEndsAt.collectAsState()
    val track = queue.getOrNull(index)
    val compact = LocalConfiguration.current.screenWidthDp < 900
    var pane by remember { mutableStateOf(Pane.Lyrics) }
    var devices by remember { mutableStateOf(false) }
    var sleep by remember { mutableStateOf(false) }

    // Le fond prend la couleur de la pochette (Sona), l'or d'Archive, ou le coucher de soleil de Vice City.
    val tint by animateColorAsState(coverColor?.let { Color(it) } ?: Color(0xFF1C1C24), tween(800), label = "tint")
    val backdrop: Brush = when (look.id) {
        ThemeId.Gta -> look.backgroundBrush ?: Brush.verticalGradient(listOf(look.background, look.background))
        ThemeId.Archive -> Brush.verticalGradient(listOf(tint.copy(alpha = 0.40f), look.background))
        ThemeId.Sona -> Brush.verticalGradient(listOf(tint, Color.Black))
    }
    Box(Modifier.fillMaxSize().background(look.background).background(backdrop)) {
        if (track == null) return@Box
        Column(Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 20.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { Nav.back() }) { Icon(Icons.Filled.KeyboardArrowDown, "Fermer", tint = look.primary, modifier = Modifier.size(34.dp)) }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    SonaText("EN LECTURE", 11.sp, FontWeight.Bold, tone = 2)
                    if (queueName.isNotBlank()) SonaText(queueName, 14.sp, FontWeight.SemiBold, tone = 1, maxLines = 1)
                }
                IconButton(onClick = { sleep = true }) {
                    Icon(Icons.Filled.Bedtime, "Minuteur", tint = if (sleepEnd != null) look.accent else look.secondary)
                }
                IconButton(onClick = { devices = true }) { Icon(Icons.Filled.Cast, "Écouter sur", tint = look.secondary) }
            }
            if (compact) {
                Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Cover(track.coverUrl, Modifier.size(150.dp))
                        Column(Modifier.weight(1f)) { TitleBlock(track) }
                    }
                    SeekBar()
                    TransportControls(Modifier.fillMaxWidth())
                    PaneSwitch(pane) { pane = it }
                    Box(Modifier.weight(1f).fillMaxWidth()) { PaneContent(pane) }
                }
            } else {
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(44.dp)) {
                    Column(Modifier.width(440.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Cover(track.coverUrl, Modifier.size(440.dp))
                        TitleBlock(track)
                        SeekBar()
                        TransportControls(Modifier.fillMaxWidth())
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PaneSwitch(pane) { pane = it }
                        Box(Modifier.weight(1f).fillMaxWidth()) { PaneContent(pane) }
                    }
                }
            }
        }
    }
    if (devices) DevicePicker { devices = false }
    if (sleep) SleepDialog { sleep = false }
}

@Composable
private fun TitleBlock(track: Track) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SonaText(track.title, 30.sp, FontWeight.ExtraBold, maxLines = 2, title = true)
        SonaText(track.artist, 19.sp, tone = 1, maxLines = 1)
    }
}

@Composable
private fun SeekBar() {
    val look = LocalLook.current
    val position by Hub.positionMs.collectAsState()
    val duration by Hub.durationMs.collectAsState()
    var drag by remember { mutableStateOf<Float?>(null) }
    val total = duration.coerceAtLeast(1L).toFloat()
    Column {
        Slider(
            value = (drag ?: position.toFloat()).coerceIn(0f, total),
            onValueChange = { drag = it },
            onValueChangeFinished = {
                drag?.let { Hub.seekTo(it / 1000.0) }
                drag = null
            },
            valueRange = 0f..total,
            colors = SliderDefaults.colors(
                thumbColor = look.primary,
                activeTrackColor = look.primary,
                inactiveTrackColor = look.primary.copy(alpha = 0.22f),
            ),
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            SonaText(formatTime((drag ?: position.toFloat()).toLong()), 13.sp, tone = 1)
            SonaText(formatTime(duration), 13.sp, tone = 1)
        }
    }
}

@Composable
private fun PaneSwitch(selected: Pane, onSelect: (Pane) -> Unit) {
    val look = LocalLook.current
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Pane.entries.forEach { p ->
            val on = p == selected
            Box(
                Modifier
                    .clip(RoundedCornerShape(50))
                    .background(if (on) look.buttonFill else look.surfaceStrong)
                    .pressable { onSelect(p) }
                    .padding(horizontal = 20.dp, vertical = 10.dp),
            ) { SonaText(p.label, 15.sp, FontWeight.SemiBold, color = if (on) look.buttonText else look.primary) }
        }
    }
}

@Composable
private fun PaneContent(pane: Pane) {
    when (pane) {
        Pane.Lyrics -> LyricsView(Modifier.fillMaxSize(), 32.sp)
        Pane.Queue -> QueuePane()
    }
}

@Composable
private fun QueuePane() {
    val queue by Hub.queue.collectAsState()
    val index by Hub.index.collectAsState()
    val state = rememberLazyListState()
    LaunchedEffect(Unit) { state.scrollToItem((index - 1).coerceAtLeast(0)) }
    LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(bottom = 24.dp)) {
        itemsIndexed(queue) { i, t -> TrackItem(t, { Hub.jumpTo(i) }, current = i == index) }
    }
}

// ── Fenêtres : écouter sur un autre appareil, minuteur de sommeil ────────────────────────

@Composable
fun DevicePicker(onDismiss: () -> Unit) {
    val look = LocalLook.current
    val devices by Hub.devices.collectAsState()
    val active by Hub.activeDeviceId.collectAsState()
    val me = Hub.settings.deviceId
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().background(look.background, RoundedCornerShape(26.dp)).glass(26.dp, strong = true).padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SonaText("Écouter sur", 24.sp, FontWeight.Bold, title = true)
            SonaText("Sona Connect : la musique passe d'un appareil à l'autre.", 14.sp, tone = 1)
            Spacer(Modifier.height(6.dp))
            if (devices.isEmpty()) SonaText("Aucun appareil connecté pour l'instant.", 15.sp, tone = 2)
            devices.forEach { d ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(look.corner)).pressable {
                        Hub.remote(if (d.isMe) me else d.id, "transfer")
                        onDismiss()
                    }.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Icon(kindIcon(d.kind), null, tint = if (d.id == active) look.accent else look.secondary, modifier = Modifier.size(28.dp))
                    Column(Modifier.weight(1f)) {
                        SonaText(if (d.isMe) "${d.name} (ce casque)" else d.name, 16.sp, FontWeight.SemiBold, maxLines = 1)
                        SonaText(if (d.id == active) "En lecture" else "Disponible", 13.sp, tone = if (d.id == active) 3 else 2)
                    }
                }
            }
            Spacer(Modifier.height(4.dp))
            PillButton("Fermer", onDismiss, Modifier.fillMaxWidth(), primary = false)
        }
    }
}

@Composable
fun SleepDialog(onDismiss: () -> Unit) {
    val look = LocalLook.current
    val end by Hub.sleepEndsAt.collectAsState()
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().background(look.background, RoundedCornerShape(26.dp)).glass(26.dp, strong = true).padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SonaText("Minuteur de sommeil", 24.sp, FontWeight.Bold, title = true)
            SonaText("La musique s'arrête en fondu à l'heure choisie.", 14.sp, tone = 1)
            Spacer(Modifier.height(4.dp))
            listOf(15, 30, 45, 60, 90).forEach { m ->
                PillButton("$m minutes", { Hub.setSleepTimer(m); onDismiss() }, Modifier.fillMaxWidth(), primary = false)
            }
            if (end != null) {
                PillButton("Annuler le minuteur", { Hub.setSleepTimer(null); onDismiss() }, Modifier.fillMaxWidth())
            }
        }
    }
}
