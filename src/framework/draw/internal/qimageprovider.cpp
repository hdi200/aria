#include "qimageprovider.h"

#include <QBuffer>
#include <QImageReader>

#include "qimagepainterprovider.h"
#include "types/pixmap.h"

#include "log.h"

using namespace muse::draw;

static const char FILE_FORMAT[] = "PNG";

std::shared_ptr<Pixmap> QImageProvider::createPixmap(const ByteArray& data) const
{
    // Aria: a Pixmap holds encoded bytes that every reader decodes with
    // QPixmap::loadFromData, which accepts any format Qt can read. Keep the
    // file's own bytes and read the size from its header, instead of decoding
    // the image and re-encoding it as PNG, which takes seconds for a large
    // picture in a title frame.
    {
        QByteArray bytes = data.toQByteArrayNoCopy();
        QBuffer buffer(&bytes);
        QImageReader reader(&buffer);
        const QSize size = reader.canRead() ? reader.size() : QSize();
        if (size.isValid() && !size.isEmpty()) {
            return std::make_shared<Pixmap>(data, Size(size.width(), size.height()));
        }
    }

    QImage image;
    image.loadFromData(data.toQByteArrayNoCopy());

    return std::make_shared<Pixmap>(Pixmap::fromQPixmap(QPixmap::fromImage(image)));
}

std::shared_ptr<Pixmap> QImageProvider::createPixmap(int w, int h, int dpm, const Color& color) const
{
    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.setDotsPerMeterX(dpm);
    image.setDotsPerMeterY(dpm);
    image.fill(color.toQColor());

    return std::make_shared<Pixmap>(Pixmap::fromQPixmap(QPixmap::fromImage(image)));
}

Pixmap QImageProvider::scaled(const Pixmap& origin, const Size& s) const
{
    QPixmap qtPixmap = Pixmap::toQPixmap(origin);
    qtPixmap = qtPixmap.scaled(s.width(), s.height());

    return Pixmap::fromQPixmap(qtPixmap);
}

std::shared_ptr<IPaintProvider> QImageProvider::painterForImage(std::shared_ptr<Pixmap> pixmap)
{
    return QImagePainterProvider::make(pixmap);
}

void QImageProvider::saveAsPng(std::shared_ptr<Pixmap> px, io::IODevice* device)
{
    QBuffer buf;
    buf.open(QIODevice::WriteOnly);
    Pixmap::toQPixmap(*px).save(&buf, FILE_FORMAT);
    device->write(buf.data());
}
